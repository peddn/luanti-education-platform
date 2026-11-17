#!/usr/bin/env bash
# Builds and starts the LEP backend for the test environment.
#   scripts/backend-run.sh
# It listens on http://127.0.0.1:8080 and keeps its database in .dev/.
# LEP_BIND and LEP_DATABASE change that. It also serves the frontend, if
# scripts/frontend-run.sh build has built it. Stop it with Ctrl+C.
#
# Settings that should stay out of the shell history, such as the password
# of the mail server, go into .dev/backend.env, one NAME=value per line.
# The folder .dev is never checked in.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

# The file is read line by line and not run: a value may hold spaces and
# characters like < and >. A variable that is already set wins.
if [ -f .dev/backend.env ]; then
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		"" | "#"*) continue ;;
		esac
		name="${line%%=*}"
		value="${line#*=}"
		if [[ ! "$name" =~ ^[A-Z_][A-Z0-9_]*$ ]] || [ "$name" = "$line" ]; then
			echo ".dev/backend.env: cannot read the line that starts with '${name:0:20}'" >&2
			exit 1
		fi
		if [ -z "${!name+x}" ]; then
			export "$name=$value"
		fi
	done <.dev/backend.env
fi

export LEP_DATABASE="${LEP_DATABASE:-$repo/.dev/backend/lep.sqlite}"
export LEP_FRONTEND="${LEP_FRONTEND:-$repo/frontend/dist}"
export RUST_LOG="${RUST_LOG:-info}"

exec cargo run --package lep-backend "$@"
