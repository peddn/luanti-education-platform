#!/usr/bin/env bash
# Creates a local Luanti user directory in .dev/ with Minetest Game,
# the LEP mods and a test world. Safe to run again.
#
# The admin of the test server is the player named in .dev/minetest.conf.
# The script asks for the name once. To skip the question, set it up front:
#   LEP_ADMIN_NAME=myname scripts/dev-setup.sh
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

# Debug helpers of the LEP mods (test places, debug commands).
if ! grep -q '^lep_debug' "$dev/minetest.conf"; then
	echo "lep_debug = true" >> "$dev/minetest.conf"
fi

# The admin gets all privileges on the test server, including lep_debug.
if ! grep -q '^name[[:space:]]*=' "$dev/minetest.conf"; then
	admin="${LEP_ADMIN_NAME:-}"
	if [ -z "$admin" ] && [ -t 0 ]; then
		read -r -p "Player name of the test server admin (empty to skip): " admin
	fi
	if [ -n "$admin" ]; then
		if [[ "$admin" =~ ^[A-Za-z0-9_-]{1,19}$ ]]; then
			echo "name = $admin" >> "$dev/minetest.conf"
			echo "Admin of the test server: $admin"
		else
			echo "Invalid player name '$admin': only letters, digits, - and _," \
				"at most 19 characters. No admin set." >&2
		fi
	else
		echo "No admin set. Debug commands need an admin:" \
			"run LEP_ADMIN_NAME=<name> scripts/dev-setup.sh"
	fi
fi

echo "Test world ready in $world"
echo "Start the server with: scripts/dev-run.sh --server"
