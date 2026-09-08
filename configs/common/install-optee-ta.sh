#!/usr/bin/env bash
# Copy OP-TEE trusted applications into a rootfs-like tree.
# Usage: install-optee-ta.sh <DEST_ROOT>
#
# Looks for signed *.ta under (first match wins):
#   $OPENTINA_OPTEE_EXPORT
#   $outDir/optee
#   $OPENTINA_BUILD_ROOT/output/<board>/optee
# only in export-ta_*/ta/. The O= tree also has ta/<uuid>/*.ta
# (intermediates / unsigned leftovers); do not treat that as a source.
set -euo pipefail

DEST_ROOT="${1:?usage: $0 <DEST_ROOT>}"
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
BUILD_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ "${OPENTINA_OPTEE:-1}" = "0" ]; then
	echo "install-optee-ta: OP-TEE disabled; skip"
	exit 0
fi

# Same glob for detect and install: signed TAs from the TA export.
TA_GLOB='export-ta_*/ta/*.ta'

has_tas() {
	local root="$1"
	[ -d "$root" ] || return 1
	compgen -G "$root/$TA_GLOB" >/dev/null 2>&1
}

resolve_export() {
	local d
	if [ -n "${OPENTINA_OPTEE_EXPORT:-}" ] && has_tas "$OPENTINA_OPTEE_EXPORT"; then
		printf '%s\n' "$OPENTINA_OPTEE_EXPORT"
		return 0
	fi
	if [ -n "${outDir:-}" ] && has_tas "${outDir%/}/optee"; then
		printf '%s\n' "${outDir%/}/optee"
		return 0
	fi
	for d in "$BUILD_ROOT"/output/*/optee; do
		has_tas "$d" || continue
		printf '%s\n' "$d"
		return 0
	done
	return 1
}

EXPORT=""
if ! EXPORT="$(resolve_export)"; then
	echo "install-optee-ta: no OP-TEE TAs found (build optee first); skip"
	exit 0
fi

n=0
mkdir -p "$DEST_ROOT/lib/optee_armtz" "$DEST_ROOT/data/tee"

shopt -s nullglob
for ta in "$EXPORT"/$TA_GLOB; do
	cp -a "$ta" "$DEST_ROOT/lib/optee_armtz/"
	n=$((n + 1))
done
shopt -u nullglob

if [ "$(id -u)" -eq 0 ]; then
	chown -R 0:0 "$DEST_ROOT/lib/optee_armtz" "$DEST_ROOT/data/tee"
fi

if [ "$n" -eq 0 ]; then
	echo "install-optee-ta: no *.ta under $EXPORT (build optee first)"
	exit 0
fi
echo "install-optee-ta: installed $n TA(s) from $EXPORT -> $DEST_ROOT/lib/optee_armtz"
