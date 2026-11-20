#!/usr/bin/env bash
# Builds the Luanti server in the version pinned in third_party/luanti.toml:
#   scripts/luanti-build.sh
# Only the server is built, without graphics and sound. The result stays
# in target/luanti/ until it is installed, which needs root:
#   sudo cmake --install target/luanti/build
# That puts luantiserver into /usr/local/bin and what it needs to run
# into /usr/local/share/luanti.
#
# Packages needed on Debian are listed in docs/betrieb.md. Needs network
# access to the source of Luanti.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
out="$repo/target/luanti"
pin="$repo/third_party/luanti.toml"

# shellcheck source=scripts/lib/third-party.sh
. "$repo/scripts/lib/third-party.sh"

value() {
	sed -n "s/^$1[[:space:]]*=[[:space:]]*\"\(.*\)\"$/\1/p" "$pin" | head -n 1
}
url="$(value repo)"
commit="$(value commit)"
version="$(value version)"
if [ -z "$url" ] || [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]] || [ -z "$version" ]; then
	echo "third_party/luanti.toml needs repo, version and commit" >&2
	exit 1
fi

mkdir -p "$out"
fetch_pinned "$out/source" "$url" "$commit"

echo "Building the Luanti server $version ..."
cmake -S "$out/source" -B "$out/build" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=/usr/local \
	-DBUILD_CLIENT=FALSE \
	-DBUILD_SERVER=TRUE \
	-DBUILD_UNITTESTS=FALSE \
	-DBUILD_DOCUMENTATION=FALSE \
	-DRUN_IN_PLACE=FALSE \
	-DENABLE_CURL=TRUE \
	-DREQUIRE_LUAJIT=TRUE \
	>"$out/configure.log" 2>&1 || {
	tail -n 30 "$out/configure.log" >&2
	echo "Configuring failed. The whole output is in target/luanti/configure.log." >&2
	exit 1
}
cmake --build "$out/build" --parallel "$(nproc)" >"$out/build.log" 2>&1 || {
	tail -n 30 "$out/build.log" >&2
	echo "Building failed. The whole output is in target/luanti/build.log." >&2
	exit 1
}

built="$("$out/source/bin/luantiserver" --version | head -n 1)"
case "$built" in
*"$version"*) ;;
*)
	echo "Built '$built', but third_party/luanti.toml says $version." >&2
	exit 1
	;;
esac
echo "Built: $built"
echo "Install it with: sudo cmake --install target/luanti/build"
