#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2019-2026 Allwinner Technology Co., Ltd.
# Clone or sync OpenTina trees from an XML manifest (sophpi-style workflow).
#
# Usage:
#   ./scripts/repo_clone.sh --gitclone scripts/opentina-manifest.xml
#   ./scripts/repo_clone.sh --sync scripts/opentina-manifest.xml
#   ./scripts/repo_clone.sh --update scripts/opentina-manifest.xml
#
# --update fast-forwards checkouts whose current branch matches the manifest
# revision to that branch on origin. Checkouts on another branch (or detached
# HEAD) are left untouched and printed at the end.
#
# Manifest: optional clone-depth on <manifest> (default for all projects) or
# on <project clone-depth="N"> (overrides). Omit or empty: full history clone.
#
# Environment:
#   OPENTINA_BUILD_ROOT   Root of this build repo (default: parent of scripts/)
#   OPENTINA_SOURCES_DIR  Where projects are placed (default: $OPENTINA_BUILD_ROOT/sources)
#   OPENTINA_REMOTE_FETCH If set, overrides every <remote fetch="..."> in the manifest

set -euo pipefail

usage() {
	echo "Usage: $0 --gitclone|--sync|--update <manifest.xml>" 1>&2
	exit 1
}

[ "${1:-}" ] || usage
mode=$1
shift
[ "${1:-}" ] || usage
manifest="$(realpath "$1")"

case "$mode" in
--gitclone | --sync | --update) ;;
*) usage ;;
esac

script_dir="$(dirname -- "$(realpath -- "$0")")"
OPENTINA_BUILD_ROOT="${OPENTINA_BUILD_ROOT:-$(dirname -- "$script_dir")}"
export OPENTINA_BUILD_ROOT
OPENTINA_SOURCES_DIR="${OPENTINA_SOURCES_DIR:-$OPENTINA_BUILD_ROOT/sources}"
export OPENTINA_SOURCES_DIR

mkdir -p "$OPENTINA_SOURCES_DIR"

# Prints records: path<TAB>url<TAB>revision<TAB>clone_depth (empty = full clone)
_manifest_records() {
	python3 - "$manifest" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()


def parse_clone_depth(value):
	"""Return '' for full clone, or a positive decimal string for git depth."""
	if value is None:
		return ""
	t = value.strip()
	if not t:
		return ""
	low = t.lower()
	if low in ("full", "0", "no", "false"):
		return ""
	if not t.isdigit() or int(t) < 1:
		raise SystemExit(
			f"invalid clone-depth {value!r} (use positive integer, full, 0, or omit)"
		)
	return t


default_depth = parse_clone_depth(root.get("clone-depth"))
remotes = {}
for el in root.findall("remote"):
	name = el.get("name")
	fetch = el.get("fetch")
	if name and fetch:
		remotes[name] = fetch

default_rev = "main"
default_remote = None
de = root.find("default")
if de is not None:
	if de.get("revision"):
		default_rev = de.get("revision")
	if de.get("remote"):
		default_remote = de.get("remote")
if default_remote is None and len(remotes) == 1:
	default_remote = next(iter(remotes))

override = __import__("os").environ.get("OPENTINA_REMOTE_FETCH")
if override:
	for k in list(remotes.keys()):
		remotes[k] = override

def join_fetch_name(fetch: str, name: str) -> str:
	name = name.strip().strip("/")
	fetch = fetch.rstrip("/")
	if fetch.endswith(".git"):
		return fetch
	return fetch + "/" + name + ".git"

for proj in root.findall("project"):
	url = proj.get("url")
	name = proj.get("name")
	relpath = proj.get("path") or name
	rev = proj.get("revision") or default_rev
	remote_name = proj.get("remote") or default_remote
	if proj.get("clone-depth") is None:
		depth = default_depth
	else:
		depth = parse_clone_depth(proj.get("clone-depth"))
	if not relpath or not name:
		continue
	if url:
		final = url
	else:
		if not remote_name or remote_name not in remotes:
			raise SystemExit(f"project {name!r}: missing remote (have {sorted(remotes)!r})")
		final = join_fetch_name(remotes[remote_name], name)
	print(f"{relpath}\t{final}\t{rev}\t{depth}")
PY
}

blue() {
	printf "\033[34m%s\033[39m\n" "$1"
}

yellow() {
	printf "\033[33m%s\033[39m\n" "$1"
}

red() {
	printf "\033[31m%s\033[39m\n" "$1"
}

# Filled by --update. Different-branch rows are path<TAB>local<TAB>manifest.
different=()
update_failed=()
updated=0
uptodate=0

# Fast-forward a checkout that is already on the manifest branch.
# Other branches are recorded and left unchanged.
_update_one() {
	local relpath=$1 dest=$2 revision=$3
	local branch sha before after

	if ! branch=$(git -C "$dest" symbolic-ref --short HEAD 2>/dev/null); then
		sha=$(git -C "$dest" rev-parse --short HEAD 2>/dev/null || echo unknown)
		different+=("${relpath}"$'\t'"detached@${sha}"$'\t'"${revision}")
		yellow "skip (different branch): $relpath (detached@${sha}, manifest=${revision})"
		return 0
	fi
	if [ "$branch" != "$revision" ]; then
		different+=("${relpath}"$'\t'"${branch}"$'\t'"${revision}")
		yellow "skip (different branch): $relpath (local=${branch}, manifest=${revision})"
		return 0
	fi

	blue "update $relpath ($revision)"
	before=$(git -C "$dest" rev-parse --short HEAD)
	if ! git -C "$dest" fetch origin "$revision"; then
		update_failed+=("${relpath}"$'\t'"fetch failed")
		red "fetch failed: $relpath"
		return 0
	fi
	if ! git -C "$dest" rev-parse --verify --quiet "origin/${revision}^{commit}" >/dev/null; then
		update_failed+=("${relpath}"$'\t'"origin/${revision} missing after fetch")
		red "origin/${revision} missing after fetch: $relpath"
		return 0
	fi
	if ! git -C "$dest" -c advice.diverging=false merge --ff-only "origin/${revision}"; then
		update_failed+=("${relpath}"$'\t'"not fast-forward")
		red "not fast-forward, left unchanged: $relpath"
		return 0
	fi
	after=$(git -C "$dest" rev-parse --short HEAD)
	if [ "$before" = "$after" ]; then
		uptodate=$((uptodate + 1))
		blue "up to date: $relpath ($revision @ ${after})"
	else
		updated=$((updated + 1))
		blue "updated: $relpath ($revision) ${before} -> ${after}"
	fi
}

_print_update_summary() {
	local row path local_rev manifest_rev reason

	echo
	blue "Update summary: ${updated} updated, ${uptodate} already up to date, ${#different[@]} different branch, ${#update_failed[@]} failed"
	if [ "${#different[@]}" -gt 0 ]; then
		echo
		yellow "Different branch (not updated):"
		printf "  %-24s %-28s %s\n" "path" "local" "manifest"
		for row in "${different[@]}"; do
			IFS="$(printf '\t')" read -r path local_rev manifest_rev <<<"$row"
			printf "  %-24s %-28s %s\n" "$path" "$local_rev" "$manifest_rev"
		done
	else
		echo
		blue "Different branch: none"
	fi
	if [ "${#update_failed[@]}" -gt 0 ]; then
		echo
		red "Failed:"
		for row in "${update_failed[@]}"; do
			IFS="$(printf '\t')" read -r path reason <<<"$row"
			printf "  %s: %s\n" "$path" "$reason"
		done
	fi
}

if [ "$mode" = "--update" ]; then
	export GIT_TERMINAL_PROMPT=0
fi

while IFS="$(printf '\t')" read -r relpath url revision clone_depth; do
	[ "$relpath" ] || continue
	dest="$OPENTINA_SOURCES_DIR/$relpath"
	if [ "$mode" = "--gitclone" ]; then
		if [ -d "$dest/.git" ]; then
			yellow "skip clone (exists): $relpath"
			continue
		fi
		if [ -n "$clone_depth" ]; then
			blue "clone (depth=$clone_depth) $relpath -> $dest"
		else
			blue "clone (full) $relpath -> $dest"
		fi
		mkdir -p "$(dirname -- "$dest")"
		if [ -n "$clone_depth" ]; then
			git clone --depth "$clone_depth" --branch "$revision" "$url" "$dest"
		else
			git clone --branch "$revision" "$url" "$dest"
		fi
	elif [ "$mode" = "--update" ]; then
		if ! [ -d "$dest/.git" ]; then
			yellow "skip update (not a git repo): $relpath"
			continue
		fi
		_update_one "$relpath" "$dest" "$revision"
	else
		if ! [ -d "$dest/.git" ]; then
			yellow "skip sync (not a git repo): $relpath"
			continue
		fi
		blue "sync $relpath"
		git -C "$dest" fetch --tags origin
		git -C "$dest" checkout "$revision"
		git -C "$dest" pull --ff-only || true
	fi
done < <(_manifest_records)

if [ "$mode" = "--update" ]; then
	_print_update_summary
	if [ "${#update_failed[@]}" -gt 0 ]; then
		exit 1
	fi
fi

blue "Done ($mode). Sources: $OPENTINA_SOURCES_DIR"
