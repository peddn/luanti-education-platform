#!/usr/bin/env bash
# Builds and starts the LEP agent for the test environment.
#   scripts/agent-run.sh          run until Ctrl+C
#   scripts/agent-run.sh check    send one report and say how it went
# The agent reports to the local backend (http://127.0.0.1:8080, or
# LEP_DEV_URL) and keeps its folder in .dev/agent/. At the first start
# the script lets the backend make a key and writes the settings to
# .dev/agent.toml. The backend does not have to run for that, but the
# agent only gets through once it does: scripts/backend-run.sh
#
#   scripts/agent-run.sh --new-key    make a new key first
#
# The agent carries the template for worlds if scripts/template-build.sh
# was run before. Without it the agent runs, but has no template.
# The folder .dev is never checked in.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

settings="$repo/.dev/agent.toml"
url="${LEP_DEV_URL:-http://127.0.0.1:8080}"
export LEP_DATABASE="${LEP_DATABASE:-$repo/.dev/backend/lep.sqlite}"
export RUST_LOG="${RUST_LOG:-info}"

if [ "${1:-}" = "--new-key" ]; then
	rm -f "$settings"
	shift
fi

if [ ! -f "$settings" ]; then
	echo "Building the backend to make a key ..."
	cargo build --quiet --package lep-backend
	output="$("$repo/target/debug/lep-backend" agent key)"
	key="$(printf '%s\n' "$output" | sed -n 's/^key: //p')"
	if [ -z "$key" ]; then
		echo "The backend gave no key." >&2
		exit 1
	fi
	mkdir -p "$repo/.dev/agent"
	# Closed to other users before the key gets in.
	(umask 077 && : >"$settings")
	{
		echo "# Settings of the agent in the test environment. Never checked in."
		echo "backend = \"$url\""
		echo "key = \"$key\""
		echo "data_dir = \"$repo/.dev/agent\""
	} >"$settings"
	echo "The settings with a new key are in .dev/agent.toml."
fi

if [ -f "$repo/target/lep-template/template.tar.gz" ]; then
	export LEP_TEMPLATE="$repo/target/lep-template/template.tar.gz"
else
	echo "No template built. For an agent with a template run scripts/template-build.sh first."
fi

exec cargo run --quiet --package lep-agent -- --config "$settings" "$@"
