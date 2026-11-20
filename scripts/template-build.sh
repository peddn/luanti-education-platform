#!/usr/bin/env bash
# Packs everything a world needs into one archive: Minetest Game and the
# third-party mods at the commits pinned in third_party/, the LEP mods of
# this repository and the licence texts. The agent embeds the archive
# when it is built with LEP_TEMPLATE pointing to it. scripts/agent-build.sh
# does both steps for a server, scripts/agent-run.sh picks the archive up
# in the test environment.
#
# The archive lands in target/lep-template/template.tar.gz. Needs network
# access to the sources of game and mods, the agent itself needs none.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
out="$repo/target/lep-template"
sources="$out/sources"
stage="$out/stage"
archive="$out/template.tar.gz"

# shellcheck source=scripts/lib/third-party.sh
. "$repo/scripts/lib/third-party.sh"
read_third_party "$repo"

mkdir -p "$sources"
rm -rf "$stage"
mkdir -p "$stage/games" "$stage/mods/lep" "$stage/licenses"

# copy_checkout <from> <to>: a fetched source without its history.
copy_checkout() {
	mkdir -p "$2"
	tar -C "$1" --exclude=./.git -cf - . | tar -C "$2" -xf -
}

fetch_pinned "$sources/minetest_game" "$game_repo" "$game_commit"
copy_checkout "$sources/minetest_game" "$stage/games/minetest_game"

for i in "${!tp_names[@]}"; do
	name="${tp_names[$i]}"
	fetch_pinned "$sources/$name" "${tp_repos[$i]}" "${tp_commits[$i]}"
	copy_checkout "$sources/$name" "$stage/mods/$name"
done

# The LEP mods as git knows them, so nothing that only lies around
# locally gets in. The tests of the cores stay out.
lep_mods=()
while IFS= read -r -d '' file; do
	case "$file" in
	mods/*/spec/*) continue ;;
	esac
	[ -f "$repo/$file" ] || continue
	mkdir -p "$stage/mods/lep/$(dirname "${file#mods/}")"
	cp "$repo/$file" "$stage/mods/lep/${file#mods/}"
done < <(git -C "$repo" ls-files -z -- mods)
for mod in "$stage"/mods/lep/lep_*/; do
	lep_mods+=("$(basename "$mod")")
done

# Licence texts of this project. Game and third-party mods bring their
# own inside their folders.
cp "$repo/LICENSE.md" "$stage/licenses/"
cp -r "$repo/LICENSES" "$stage/licenses/"

if [ -n "$(find "$stage" -type l -print -quit)" ]; then
	echo "The template must not contain links:" >&2
	find "$stage" -type l >&2
	exit 1
fi
for folder in "$stage/games/minetest_game" "$stage"/mods/*/; do
	[ "$folder" = "$stage/mods/lep/" ] && continue
	if [ -z "$(find "$folder" -maxdepth 1 -type f -iname 'licen[cs]e*' -print -quit)" ]; then
		echo "No licence text found in ${folder#"$stage/"}" >&2
		exit 1
	fi
done

# What is inside, for people and for the agent.
{
	echo "# Template for the worlds of the Luanti Education Platform."
	printf 'lep_mods = ['
	sep=""
	for mod in "${lep_mods[@]}"; do
		printf '%s"%s"' "$sep" "$mod"
		sep=", "
	done
	echo "]"
	echo
	echo "[game]"
	echo "name = \"minetest_game\""
	echo "repo = \"$game_repo\""
	echo "commit = \"$game_commit\""
	echo "license = \"$game_license\""
	for i in "${!tp_names[@]}"; do
		echo
		echo "[[mods]]"
		echo "name = \"${tp_names[$i]}\""
		echo "repo = \"${tp_repos[$i]}\""
		echo "commit = \"${tp_commits[$i]}\""
		echo "license = \"${tp_licenses[$i]}\""
	done
	echo
	echo "[settings]"
	for setting in "${tp_settings[@]}"; do
		echo "${setting%% = *} = \"${setting#* = }\""
	done
} >"$stage/template.toml"

# Every file with its checksum. The agent checks them after unpacking,
# and the checksum of this list is the version of the template: it only
# depends on what is inside, not on the machine that packed it.
(
	cd "$stage"
	export LC_ALL=C
	find . -type f ! -name files.sha256 -print0 | sort -z | xargs -0 sha256sum >files.sha256
)

# Sorted, without times and owners, so the same input gives the same
# archive.
tar -C "$stage" --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
	--mode='u=rwX,go=rX' -cf - . | gzip -n -9 >"$archive.tmp"
mv "$archive.tmp" "$archive"

version="$(sha256sum "$stage/files.sha256" | cut -c1-12)"
echo "Template $version: $(wc -l <"$stage/files.sha256") files," \
	"$(du -h "$archive" | cut -f1) in target/lep-template/template.tar.gz"
