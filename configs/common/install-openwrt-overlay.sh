#!/usr/bin/env bash
# Overlay OpenTina files onto an unpacked OpenWrt rootfs (preinit, fw_printenv, board.d).
# Usage: install-openwrt-overlay.sh <DEST_ROOT>
set -euo pipefail

DEST_ROOT="${1:?usage: $0 <DEST_ROOT>}"
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
FILES="${OPENTINA_OPENWRT_FILES:-$SCRIPT_DIR/openwrt-files}"

if [ ! -d "$FILES" ]; then
	echo "install-openwrt-overlay: missing $FILES" >&2
	exit 1
fi

cp -a "$FILES"/. "$DEST_ROOT"/

mkdir -p "$DEST_ROOT/usr/sbin"
chmod 755 "$DEST_ROOT/usr/sbin/fw_printenv"
ln -sfn fw_printenv "$DEST_ROOT/usr/sbin/fw_setenv"
# Some images also ship /sbin copies.
if [ -e "$DEST_ROOT/sbin/fw_printenv" ] || [ -L "$DEST_ROOT/sbin/fw_printenv" ]; then
	ln -sfn ../usr/sbin/fw_printenv "$DEST_ROOT/sbin/fw_printenv"
	ln -sfn ../usr/sbin/fw_setenv "$DEST_ROOT/sbin/fw_setenv"
fi

chmod 644 "$DEST_ROOT/lib/preinit/79_move_config"
chmod 755 "$DEST_ROOT/etc/board.d/02_network_opentina"

if [ "$(id -u)" -eq 0 ]; then
	chown 0:0 "$DEST_ROOT/usr/sbin/fw_printenv" "$DEST_ROOT/usr/sbin/fw_setenv" \
		"$DEST_ROOT/lib/preinit/79_move_config" \
		"$DEST_ROOT/etc/board.d/02_network_opentina"
fi

echo "install-openwrt-overlay: applied $FILES -> $DEST_ROOT"
