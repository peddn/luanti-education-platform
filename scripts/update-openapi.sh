#!/usr/bin/env bash
# Writes the description of the interface into api/openapi.json, from the
# Rust types. Run it after changing crates/protocol or the routes of the
# backend, and commit the result.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p api
cargo run --quiet --package lep-backend -- openapi > api/openapi.json.tmp
mv api/openapi.json.tmp api/openapi.json
echo "api/openapi.json written."
