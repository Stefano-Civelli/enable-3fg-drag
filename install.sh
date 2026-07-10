#!/usr/bin/env bash
# Install enable-3fg-drag.
#
# Builds the shim, installs it to /usr/lib, and wires it into your
# compositor by one of two methods:
#
#   kwin    Scoped to KDE Plasma Wayland only: a systemd user drop-in that
#           preloads the shim into plasma-kwin_wayland.service. Nothing else
#           in the system loads it. (KWin's binary has a file capability, so
#           the loader runs in secure-execution mode and only honours a
#           preload given as a bare soname from a standard lib dir with the
#           setuid bit set — which is why the shim goes in /usr/lib mode 4755.)
#
#   global  Any Wayland compositor: adds the shim to /etc/ld.so.preload.
#           Honoured everywhere including secure-execution processes. The
#           shim has no libinput dependency and is inert in non-libinput
#           processes, so this is cheap; it is simply less surgical than the
#           per-compositor method.
#
# With no argument the method is auto-detected (kwin if the KWin unit
# exists, else global). Override with:  ./install.sh --method global
#
# Needs sudo (writes /usr/lib and, for global, /etc/ld.so.preload).
# Activates on your next log out / log in. Reverse with ./uninstall.sh.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
soname="libenable-3fg-drag.so"
sofile="/usr/lib/$soname"
preload_file="/etc/ld.so.preload"
dropin_dir="$HOME/.config/systemd/user/plasma-kwin_wayland.service.d"
dropin="$dropin_dir/enable-3fg-drag.conf"

method=""
while [ $# -gt 0 ]; do
	case "$1" in
	--method) method="$2"; shift 2 ;;
	--method=*) method="${1#*=}"; shift ;;
	*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

if [ -z "$method" ]; then
	if systemctl --user cat plasma-kwin_wayland.service >/dev/null 2>&1; then
		method="kwin"
	else
		method="global"
	fi
	echo "==> Auto-detected method: $method"
fi

# --- libinput version sanity check (advisory only) ---------------------
# The shim safely no-ops on libinput < 1.28 (its 3fg_drag dlsym lookups just
# resolve to NULL), so this never blocks the install; it only warns early.
# The `libinput` CLI ships separately in libinput-tools, which desktops don't
# pull in — so fall back to pkg-config, whose metadata rides along with the
# dev headers the shim already needs to compile. If neither answers, stay
# silent rather than cry wolf; the post-login journal line printed below is
# the authoritative check. (grep isolates the version and strips Debian
# epoch/revision like "2:1.25.0-1ubuntu2" -> "1.25.0" so sort -V stays honest;
# the `|| true`s keep a failed probe from tripping `set -e`/`pipefail`.)
ver="$(libinput --version 2>/dev/null || pkg-config --modversion libinput 2>/dev/null || true)"
ver="$(printf '%s' "$ver" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
if [ -n "$ver" ] && [ "$(printf '%s\n1.28\n' "$ver" | sort -V | head -1)" != "1.28" ]; then
	echo "WARNING: libinput $ver is older than 1.28; native 3-finger drag" >&2
	echo "         may be unavailable. 1.31+ is recommended (adds fast-swipe)." >&2
fi

echo "==> Building the shim"
make -C "$here" clean >/dev/null
make -C "$here"

echo "==> Installing $sofile (mode 4755)"
sudo install -m 4755 -o root -g root "$here/$soname" "$sofile"
sudo ldconfig

case "$method" in
kwin)
	echo "==> Writing systemd drop-in (scoped to the compositor only)"
	mkdir -p "$dropin_dir"
	cat >"$dropin" <<EOF
# Preload enable-3fg-drag into KWin only. Bare soname (not a path) so KWin's
# secure-execution loader honours it. See the enable-3fg-drag project.
[Service]
Environment=LD_PRELOAD=$soname
EOF
	systemctl --user daemon-reload
	;;
global)
	echo "==> Adding $sofile to $preload_file"
	if ! sudo grep -qxF "$sofile" "$preload_file" 2>/dev/null; then
		echo "$sofile" | sudo tee -a "$preload_file" >/dev/null
	fi
	;;
*)
	echo "unknown method: $method (use kwin or global)" >&2
	exit 2
	;;
esac

cat <<EOF

==> Installed (method: $method).

   Log out and back in (a full session restart) to activate.
   Then three fingers DRAG; four-finger swipes keep working as before.

   Verify it engaged:
EOF
if [ "$method" = kwin ]; then
	echo "     journalctl --user -u plasma-kwin_wayland -b | grep enable-3fg-drag"
else
	echo "     journalctl --user -b | grep enable-3fg-drag   # (compositor's journal)"
fi
echo "     # -> [enable-3fg-drag] enabled 3-finger drag on \"<device>\": Success"
echo
echo "   Revert:  ./uninstall.sh   (then log out/in)"
