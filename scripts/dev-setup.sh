#!/usr/bin/env bash
# Creates a local Luanti user directory in .dev/ with Minetest Game,
# the LEP mods and a test world. Safe to run again.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
dev="$repo/.dev"
world="$dev/worlds/dev"
game_repo="https://github.com/luanti-org/minetest_game"

mkdir -p "$dev/games" "$dev/mods" "$world"

if [ ! -d "$dev/games/minetest_game" ]; then
	echo "Fetching Minetest Game ..."
	git clone --depth 1 "$game_repo" "$dev/games/minetest_game"
fi

# The LEP modpack is linked, so changes in mods/ apply without copying.
ln -sfn "$repo/mods" "$dev/mods/lep"

# Enable every LEP mod in the test world.
{
	echo "gameid = minetest"
	echo "backend = sqlite3"
	echo "player_backend = sqlite3"
	echo "auth_backend = sqlite3"
	echo "mod_storage_backend = sqlite3"
	for mod in "$repo"/mods/lep_*/; do
		[ -d "$mod" ] || continue
		echo "load_mod_$(basename "$mod") = true"
	done
} > "$world/world.mt"

if [ ! -f "$dev/minetest.conf" ]; then
	cat > "$dev/minetest.conf" <<'CONF'
# Local settings for the LEP test world. Not checked in.
creative_mode = false
enable_damage = true
CONF
fi

echo "Test world ready in $world"
echo "Start it with: scripts/dev-run.sh"
