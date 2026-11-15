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
game_repo="https://github.com/luanti-org/minetest_game"

mkdir -p "$dev/games" "$dev/mods" "$dev/third_party" "$world"

if [ ! -d "$dev/games/minetest_game" ]; then
	echo "Fetching Minetest Game ..."
	git clone --depth 1 "$game_repo" "$dev/games/minetest_game"
fi

# The LEP modpack is linked, so changes in mods/ apply without copying.
ln -sfn "$repo/mods" "$dev/mods/lep"

# Third-party mods are fetched at the commit pinned in third_party/mods.toml.
# The file is read line by line: "[name]", then repo = "..." and
# commit = "..." in any order.
third_party_mods=()
fetch_third_party() {
	local name="$1" url="$2" commit="$3"
	local target="$dev/third_party/$name"
	if [ -z "$url" ] || [ -z "$commit" ]; then
		echo "third_party/mods.toml: [$name] needs repo and commit" >&2
		exit 1
	fi
	if [ "$(git -C "$target" rev-parse HEAD 2>/dev/null || true)" != "$commit" ]; then
		echo "Fetching $name at ${commit:0:10} ..."
		rm -rf "$target"
		git init --quiet "$target"
		git -C "$target" fetch --quiet --depth 1 "$url" "$commit"
		git -C "$target" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
	fi
	ln -sfn "$target" "$dev/mods/$name"
	third_party_mods+=("$name")
}

tp_name="" tp_repo="" tp_commit=""
while IFS= read -r line || [ -n "$line" ]; do
	if [[ "$line" =~ ^\[([A-Za-z0-9_]+)\]$ ]]; then
		[ -z "$tp_name" ] || fetch_third_party "$tp_name" "$tp_repo" "$tp_commit"
		tp_name="${BASH_REMATCH[1]}" tp_repo="" tp_commit=""
	elif [[ "$line" =~ ^repo[[:space:]]*=[[:space:]]*\"(.+)\"$ ]]; then
		tp_repo="${BASH_REMATCH[1]}"
	elif [[ "$line" =~ ^commit[[:space:]]*=[[:space:]]*\"([0-9a-f]{40})\"$ ]]; then
		tp_commit="${BASH_REMATCH[1]}"
	fi
done < "$repo/third_party/mods.toml"
[ -z "$tp_name" ] || fetch_third_party "$tp_name" "$tp_repo" "$tp_commit"

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
