#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2019-2026 Allwinner Technology Co., Ltd.

availableComponents=(optee atf uboot linux br2 bootfs image)

OPENTINA_BUILD_ROOT="$(dirname -- "$(realpath -- "$0")")"
export OPENTINA_BUILD_ROOT

# Firmware trees live under this build repo (clone via scripts/repo_clone.sh).
sdkRoot="$OPENTINA_BUILD_ROOT/sources"
export sdkRoot

# --- Optional leading flags (stripped before board/init/targets parsing) ---
while [ $# -gt 0 ]; do
	case "$1" in
	--docker-shell)
		OPENTINA_DOCKER_SHELL=1
		shift
		break
		;;
	--docker)
		OPENTINA_DOCKER=1
		shift
		;;
	--optee)
		OPENTINA_OPTEE=1
		shift
		;;
	--no-optee)
		OPENTINA_OPTEE=0
		shift
		;;
	*)
		break
		;;
	esac
done

# Interactive shell in the build image (same mounts as --docker builds).
if [ -n "${OPENTINA_DOCKER_SHELL:-}" ]; then
	if [ -n "${OPENTINA_SKIP_DOCKER:-}" ]; then
		echo "OPENTINA_SKIP_DOCKER is set; refusing --docker-shell." >&2
		exit 1
	fi
	if [ -n "${OPENTINA_IN_DOCKER:-}" ] || [ -e /.dockerenv ]; then
		echo "Already inside a container." >&2
		exit 1
	fi
	command -v docker >/dev/null 2>&1 || {
		echo "docker: not found." >&2
		exit 127
	}
	exec "$OPENTINA_BUILD_ROOT/scripts/docker-exec.sh" --shell "$@"
fi

# Opt-in: build inside Ubuntu 24.04 (OPENTINA_DOCKER=1 or one or more --docker flags).
if [ -z "${OPENTINA_SKIP_DOCKER:-}" ] && [ -z "${OPENTINA_IN_DOCKER:-}" ] && [ ! -e /.dockerenv ] &&
	[ -n "${OPENTINA_DOCKER:-}" ] && [ "${OPENTINA_DOCKER}" != "0" ] &&
	command -v docker >/dev/null 2>&1; then
	exec "$OPENTINA_BUILD_ROOT/scripts/docker-exec.sh" "$@"
fi

if [ -n "${OPENTINA_DOCKER:-}" ] && [ "${OPENTINA_DOCKER}" != "0" ] &&
	[ -z "${OPENTINA_SKIP_DOCKER:-}" ] && [ -z "${OPENTINA_IN_DOCKER:-}" ] && [ ! -e /.dockerenv ] &&
	! command -v docker >/dev/null 2>&1; then
	echo "OPENTINA_DOCKER=1 but docker is not in PATH; staying on host." >&2
fi

msg() {
	echo "$1" 2>&1
}

if [ -t 1 ]; then
	red_msg() {
		echo -ne "\033[31m"
		msg "$1"
		echo -ne "\033[39m"
	}

	yellow_msg() {
		echo -ne "\033[33m"
		msg "$1"
		echo -ne "\033[39m"
	}

	blue_msg() {
		echo -ne "\033[34m"
		msg "$1"
		echo -ne "\033[39m"
	}
else
	red_msg() {
		msg "$1"
	}

	yellow_msg() {
		msg "$1"
	}

	blue_msg() {
		msg "$1"
	}
fi

# shellcheck source=scripts/opentina-boards.sh
source "$OPENTINA_BUILD_ROOT/scripts/opentina-boards.sh"

error() {
	red_msg "$1"
	exit 1
}

usage() {
	[ "$1" ] && msg "$1"

	echo "From $OPENTINA_BUILD_ROOT:"
	echo "  Host (default):"
	echo "    ./build.sh ..."
	echo "  Docker (Ubuntu 24.04 image, same repo mount):"
	echo "    ./build.sh --docker ...          # one-shot: prefix once"
	echo "    OPENTINA_DOCKER=1 ./build.sh ...   # or export for the session"
	echo "    ./build.sh --docker-shell        # interactive shell in the image"
	echo "    OPENTINA_DOCKER_IMAGE=tag:local ...  # override image name"
	echo "    OPENTINA_DOCKER_HOSTNAME=name ...  # container hostname (default opentina)"
	echo "  Force host even with OPENTINA_DOCKER in env:"
	echo "    OPENTINA_SKIP_DOCKER=1 ./build.sh ..."
	echo
	echo "  OP-TEE (optional; default on):"
	echo "    ./build.sh --optee ...           # enable BL32 + kernel driver + TAs"
	echo "    ./build.sh --no-optee ...        # ATF SPD=none, no BL32 / TAs"
	echo "    OPENTINA_OPTEE=0 ./build.sh ...  # same as --no-optee (board config may set a default)"
	echo
	echo "  ./build.sh targets | list"
	echo "      List board targets (BOARD_NAME) and root filesystem types"
	echo
	echo "  ./build.sh init [MANIFEST_XML]"
	echo "      Clone sources (default: scripts/opentina-manifest.xml)"
	echo
	echo "  ./build.sh <BOARD_NAME> <build|clean> [COMPONENT]"
	echo "  ./build.sh <BOARD_NAME> <ROOTFS> <build|clean> [COMPONENT]"
	echo "      ROOTFS: buildroot (default if omitted), debian, ubuntu, yocto, openwrt"
	echo
	echo "	Action is either build or clean"
	echo
	echo "	Available components"
	echo "		${availableComponents[@]}"

	exit 1
}

requires() {
	[ -f "$outDir/.done.${1}" ] ||
	error "Building component \"$gThisComponent requires \"$1\", which hasn't been built yet."
}

if [ "$#" -eq 0 ]; then
	opentina_list_targets
	echo
	msg "Run: ./build.sh <BOARD_NAME> [ROOTFS] <build|clean> [COMPONENT]"
	msg "Use ./build.sh targets to show this list again."
	exit 0
fi

if [ "$1" = targets ] || [ "$1" = list ]; then
	opentina_list_targets
	exit 0
fi

if [ "${1:-}" = init ]; then
	shift
	if [ "${1:-}" ]; then
		manifest="$(realpath -- "$1")"
	else
		manifest="$(realpath -- "$OPENTINA_BUILD_ROOT/scripts/opentina-manifest.xml")"
	fi
	[ -f "$manifest" ] || error "Manifest not found: $manifest"
	exec "$OPENTINA_BUILD_ROOT/scripts/repo_clone.sh" --gitclone "$manifest"
fi

boardName="$1"
shift
[ "$boardName" ] || usage "Missing board name"

if ! boardConfigDir=$(opentina_config_dir_for_board_name "$boardName"); then
	rc=$?
	opentina_list_targets
	echo
	[ "$rc" = 2 ] && error "Duplicate BOARD_NAME \"$boardName\" under configs/"
	error "Unknown board BOARD_NAME \"$boardName\""
fi

if [ "${1:-}" = build ] || [ "${1:-}" = clean ]; then
	OPENTINA_ROOTFS=buildroot
	action=$1
	shift
elif opentina_rootfs_is_known "${1:-}"; then
	OPENTINA_ROOTFS=$1
	shift
	case "${1:-}" in
	build | clean)
		action=$1
		shift
		;;
	*)
		usage "Missing build|clean after rootfs type \"$OPENTINA_ROOTFS\""
		;;
	esac
else
	usage "Expected build|clean, or a rootfs (${opentina_rootfs_types[*]}) then build|clean"
fi

export OPENTINA_ROOTFS

opentina_rootfs_component() {
	case "$OPENTINA_ROOTFS" in
	ubuntu) printf '%s' ubuntu ;;
	debian) printf '%s' debian ;;
	yocto) printf '%s' yocto ;;
	openwrt) printf '%s' openwrt ;;
	*) printf '%s' br2 ;;
	esac
}

userComponents="$*"

# Setting up default building parameters
[ "$JOBS" ] || JOBS="$(nproc)"
outDir="$OPENTINA_BUILD_ROOT/output/$boardName/"
export outDir

# Setting up default make parameters
export MAKEFLAGS="$MAKEFLAGS -j$JOBS"

mkdir -p "$outDir"

source "$OPENTINA_BUILD_ROOT/configs/$boardConfigDir/config"

# Board config may set OPENTINA_OPTEE="${OPENTINA_OPTEE:-1}"; CLI/env already won.
if opentina_optee_enabled; then
	export OPENTINA_OPTEE=1
	export OPENTINA_OPTEE_EXPORT="${outDir%/}/optee"
	availableComponents=(optee atf uboot linux "$(opentina_rootfs_component)" bootfs image)
	blue_msg "OP-TEE: enabled (BL32 + kernel driver + TAs)"
else
	export OPENTINA_OPTEE=0
	unset OPENTINA_OPTEE_EXPORT
	availableComponents=(atf uboot linux "$(opentina_rootfs_component)" bootfs image)
	# Still clean leftover tee.bin / $O/optee when OP-TEE is off.
	if [ "$action" = clean ]; then
		availableComponents=(optee "${availableComponents[@]}")
	fi
	blue_msg "OP-TEE: disabled (ATF SPD=none, no BL32 / TAs)"
fi

component="$userComponents"
[ "$component" ] || component="${availableComponents[*]}"

if [ "$action" = build ]; then
	for _c in $component; do
		if [ "$_c" = optee ] && ! opentina_optee_enabled; then
			error "OP-TEE is disabled (OPENTINA_OPTEE=0). Enable with --optee or OPENTINA_OPTEE=1."
		fi
	done
	unset _c
fi

source "$OPENTINA_BUILD_ROOT/scripts/recipes.sh"

for comp in ${component}; do
	todo="${action}_${comp}"
	gThisComponent="$comp"

	if ! declare -F "$todo" > /dev/null 2>/dev/null; then
		error "Action \"$action\" for component \"$comp\" isn't defined!"
	fi

	blue_msg "========== $action component $comp (rootfs=$OPENTINA_ROOTFS) =========="
	"$todo"
	cd "$OPENTINA_BUILD_ROOT"
	blue_msg "========== $action component $comp done ========"

	if [ "$action" = build ]; then
		touch "$outDir/.done.$comp"
	else
		rm -f "$outDir/.done.$comp"
	fi
done
