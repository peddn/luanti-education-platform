#!/usr/bin/env bash
# Builds and starts the LEP backend for the test environment.
#   scripts/backend-run.sh
# It listens on http://127.0.0.1:8080 and keeps its database in .dev/.
# LEP_BIND and LEP_DATABASE change that. It also serves the frontend, if
# scripts/frontend-run.sh build has built it. Stop it with Ctrl+C.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

export LEP_DATABASE="${LEP_DATABASE:-$repo/.dev/backend/lep.sqlite}"
export LEP_FRONTEND="${LEP_FRONTEND:-$repo/frontend/dist}"
export RUST_LOG="${RUST_LOG:-info}"

exec cargo run --package lep-backend "$@"
