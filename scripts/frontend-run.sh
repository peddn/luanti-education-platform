#!/usr/bin/env bash
# Works on the frontend of the web application.
#   scripts/frontend-run.sh          starts the development server on
#                                    http://127.0.0.1:5173, it reloads the
#                                    page after every change
#   scripts/frontend-run.sh build    builds the frontend into frontend/dist,
#                                    from where the backend serves it
# The development server passes requests for /api on to the backend on
# http://127.0.0.1:8080. LEP_DEV_URL changes that. Stop it with Ctrl+C.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo/frontend"

if ! command -v npm >/dev/null; then
	echo "npm not found. Install Node.js with npm first." >&2
	exit 1
fi

# Install the packages if they are missing or older than the lock file.
if [ ! -d node_modules ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then
	echo "== npm ci"
	npm ci
fi

case "${1:-dev}" in
dev)
	exec npm run dev
	;;
build)
	npm run build
	echo "Built into frontend/dist. Start the backend with scripts/backend-run.sh."
	;;
*)
	echo "usage: scripts/frontend-run.sh [build]" >&2
	exit 1
	;;
esac
