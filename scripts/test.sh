#!/usr/bin/env bash
# Runs all static checks and unit tests for the Lua mods.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== luacheck"
luacheck mods

echo "== busted"
busted
