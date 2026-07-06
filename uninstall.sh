#!/usr/bin/env bash
# Fully revert install.sh, whichever method was used. Removes the systemd
# drop-in, the /etc/ld.so.preload entry, and the installed library.
# Takes effect on next log out / log in. Needs sudo.
set -euo pipefail

soname="libenable-3fg-drag.so"
sofile="/usr/lib/$soname"
preload_file="/etc/ld.so.preload"
dropin_dir="$HOME/.config/systemd/user/plasma-kwin_wayland.service.d"
dropin="$dropin_dir/enable-3fg-drag.conf"

echo "==> Removing systemd drop-in (kwin method), if present"
if [ -f "$dropin" ]; then
	rm -f "$dropin"
	rmdir "$dropin_dir" 2>/dev/null || true
	systemctl --user daemon-reload
fi

echo "==> Removing $preload_file entry (global method), if present"
if [ -f "$preload_file" ] && grep -qxF "$sofile" "$preload_file" 2>/dev/null; then
	sudo grep -vxF "$sofile" "$preload_file" | sudo tee "$preload_file.tmp" >/dev/null
	sudo mv "$preload_file.tmp" "$preload_file"
	# leave an empty file rather than deleting a system config
fi

echo "==> Removing $sofile"
sudo rm -f "$sofile"
sudo ldconfig

cat <<'EOF'

==> Reverted. Log out and back in to fully unload the shim.
EOF
