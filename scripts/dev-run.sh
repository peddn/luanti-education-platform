#!/usr/bin/env bash
# Starts Luanti with the local user directory from .dev/.
#   scripts/dev-run.sh            start the test world in the client
#   scripts/dev-run.sh --server   start a headless server on port 30000
# Further arguments are passed on to Luanti.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
dev="$repo/.dev"
world="$dev/worlds/dev"

if [ ! -f "$world/world.mt" ]; then
	echo "No test world found. Run scripts/dev-setup.sh first." >&2
	exit 1
fi

# LUANTI_USER_PATH replaces MINETEST_USER_PATH in newer versions.
export LUANTI_USER_PATH="$dev"
export MINETEST_USER_PATH="$dev"

if [ "${1:-}" = "--server" ]; then
	shift
	exec luanti --server --config "$dev/minetest.conf" --world "$world" "$@"
fi

exec luanti --config "$dev/minetest.conf" --go --world "$world" "$@"
