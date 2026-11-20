# Shared by scripts/dev-setup.sh and scripts/template-build.sh: reads the
# pinned versions in third_party/ and fetches them. Meant to be sourced.
#
# After read_third_party these are set:
#   game_repo, game_commit, game_license
#   tp_names, tp_repos, tp_commits, tp_licenses   one entry per mod
#   tp_settings                                   "key = value" lines

# fetch_pinned <folder> <url> <commit>
# Makes <folder> a checkout of exactly this commit. Does nothing if it
# already is one.
fetch_pinned() {
	local target="$1" url="$2" commit="$3"
	if [ "$(git -C "$target" rev-parse HEAD 2>/dev/null || true)" = "$commit" ]; then
		return
	fi
	echo "Fetching $(basename "$target") at ${commit:0:10} ..."
	rm -rf "$target"
	git init --quiet "$target"
	git -C "$target" fetch --quiet --depth 1 "$url" "$commit"
	git -C "$target" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
}

# read_third_party <repo root>
# The files are read line by line: "[name]", then repo = "...",
# commit = "..." and license = "..." in any order.
read_third_party() {
	local root="$1" line name="" repo="" commit="" license="" value

	game_repo="" game_commit="" game_license=""
	while IFS= read -r line || [ -n "$line" ]; do
		if [[ "$line" =~ ^repo[[:space:]]*=[[:space:]]*\"(.+)\"$ ]]; then
			game_repo="${BASH_REMATCH[1]}"
		elif [[ "$line" =~ ^commit[[:space:]]*=[[:space:]]*\"([0-9a-f]{40})\"$ ]]; then
			game_commit="${BASH_REMATCH[1]}"
		elif [[ "$line" =~ ^license[[:space:]]*=[[:space:]]*\"(.+)\"$ ]]; then
			game_license="${BASH_REMATCH[1]}"
		fi
	done <"$root/third_party/game.toml"
	if [ -z "$game_repo" ] || [ -z "$game_commit" ]; then
		echo "third_party/game.toml needs repo and commit" >&2
		exit 1
	fi

	tp_names=() tp_repos=() tp_commits=() tp_licenses=() tp_settings=()
	_keep_mod() {
		[ -n "$name" ] || return 0
		if [ -z "$repo" ] || [ -z "$commit" ]; then
			echo "third_party/mods.toml: [$name] needs repo and commit" >&2
			exit 1
		fi
		tp_names+=("$name") tp_repos+=("$repo") tp_commits+=("$commit") tp_licenses+=("$license")
	}
	while IFS= read -r line || [ -n "$line" ]; do
		if [[ "$line" =~ ^\[([A-Za-z0-9_]+)\]$ ]]; then
			_keep_mod
			name="${BASH_REMATCH[1]}" repo="" commit="" license=""
		elif [[ "$line" =~ ^repo[[:space:]]*=[[:space:]]*\"(.+)\"$ ]]; then
			repo="${BASH_REMATCH[1]}"
		elif [[ "$line" =~ ^commit[[:space:]]*=[[:space:]]*\"([0-9a-f]{40})\"$ ]]; then
			commit="${BASH_REMATCH[1]}"
		elif [[ "$line" =~ ^license[[:space:]]*=[[:space:]]*\"(.+)\"$ ]]; then
			license="${BASH_REMATCH[1]}"
		elif [[ "$line" =~ ^settings\.([A-Za-z0-9_.]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
			value="${BASH_REMATCH[2]}"
			value="${value%\"}"
			tp_settings+=("${BASH_REMATCH[1]} = ${value#\"}")
		fi
	done <"$root/third_party/mods.toml"
	_keep_mod
}
