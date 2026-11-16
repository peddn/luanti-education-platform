#!/usr/bin/env bash
# Writes the description of the interface into api/openapi.json, from the
# Rust types, and from that the types of the frontend into
# frontend/src/api/schema.d.ts. Run it after changing crates/protocol or
# the routes of the backend, and commit the result.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p api
cargo run --quiet --package lep-backend -- openapi > api/openapi.json.tmp
mv api/openapi.json.tmp api/openapi.json
echo "api/openapi.json written."

if [ -d frontend/node_modules ]; then
	(cd frontend && npm run --silent types)
	echo "frontend/src/api/schema.d.ts written."
else
	echo "frontend/node_modules is missing, the types of the frontend were" >&2
	echo "not written. Run scripts/frontend-run.sh build once, then again." >&2
fi
