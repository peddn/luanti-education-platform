#!/usr/bin/env bash
# Connects the test world to the local backend.
#   scripts/dev-bridge.sh
# Creates the world "dev" in the backend's database (or gives it a new
# key) and writes address, key and the permission for network access into
# .dev/minetest.conf. The backend does not have to run for this.
# Afterwards start both:  scripts/backend-run.sh  and
# scripts/dev-run.sh --server
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
conf="$repo/.dev/minetest.conf"
name="${LEP_DEV_WORLD:-dev}"
url="${LEP_DEV_URL:-http://127.0.0.1:8080}"

if [ ! -f "$conf" ]; then
	echo "No test world found. Run scripts/dev-setup.sh first." >&2
	exit 1
fi

cd "$repo"
export LEP_DATABASE="${LEP_DATABASE:-$repo/.dev/backend/lep.sqlite}"

echo "Building the backend ..."
cargo build --quiet --package lep-backend
backend="$repo/target/debug/lep-backend"

if output="$("$backend" world add "$name" 2>/dev/null)"; then
	echo "World '$name' created in the backend."
else
	output="$("$backend" world rekey "$name")"
	echo "World '$name' exists already, it got a new key."
fi
key="$(printf '%s\n' "$output" | sed -n 's/^key: //p')"
if [ -z "$key" ]; then
	echo "The backend gave no key." >&2
	exit 1
fi

# Replace earlier values, keep everything else.
grep -v -e '^lep_bridge_url' -e '^lep_bridge_key' -e '^secure\.http_mods' "$conf" > "$conf.tmp" || true
{
	cat "$conf.tmp"
	echo "secure.http_mods = lep_bridge"
	echo "lep_bridge_url = $url"
	echo "lep_bridge_key = $key"
} > "$conf"
rm -f "$conf.tmp"

echo "Address and key are in .dev/minetest.conf."
echo "Start the backend:  scripts/backend-run.sh"
echo "Start the world:    scripts/dev-run.sh --server"
