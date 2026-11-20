#!/usr/bin/env bash
# Creates a local Luanti user directory in .dev/ with Minetest Game,
# the LEP mods, the third-party mods and a test world. Safe to run again.
#
# The admin of the test server is the player named in .dev/minetest.conf.
# The script asks for the name once. To skip the question, set it up front:
#   LEP_ADMIN_NAME=myname scripts/dev-setup.sh
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
dev="$repo/.dev"
world="$dev/worlds/dev"

mkdir -p "$dev/games" "$dev/mods" "$dev/third_party" "$world"

# Game and third-party mods are fetched at the commits pinned in
# third_party/game.toml and third_party/mods.toml.
# shellcheck source=scripts/lib/third-party.sh
. "$repo/scripts/lib/third-party.sh"
read_third_party "$repo"

fetch_pinned "$dev/games/minetest_game" "$game_repo" "$game_commit"

# The LEP modpack is linked, so changes in mods/ apply without copying.
ln -sfn "$repo/mods" "$dev/mods/lep"

third_party_mods=("${tp_names[@]}")
third_party_settings=("${tp_settings[@]}")
for i in "${!tp_names[@]}"; do
	fetch_pinned "$dev/third_party/${tp_names[$i]}" "${tp_repos[$i]}" "${tp_commits[$i]}"
	ln -sfn "$dev/third_party/${tp_names[$i]}" "$dev/mods/${tp_names[$i]}"
done

# Enable every LEP mod and every third-party mod in the test world.
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
	for mod in "${third_party_mods[@]}"; do
		echo "load_mod_$mod = true"
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

# Settings of the third-party mods. An existing line is replaced.
for setting in "${third_party_settings[@]}"; do
	key="${setting%% = *}"
	grep -v "^${key}[[:space:]]*=" "$dev/minetest.conf" > "$dev/minetest.conf.tmp" || true
	mv "$dev/minetest.conf.tmp" "$dev/minetest.conf"
	echo "$setting" >> "$dev/minetest.conf"
done

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
