#!/usr/bin/env bash
# Runs all static checks and unit tests: Lua mods, Rust backend and
# frontend.
#   scripts/test.sh            everything
#   scripts/test.sh lua        only the Lua mods
#   scripts/test.sh rust       only the Rust packages
#   scripts/test.sh frontend   only the frontend
set -euo pipefail

cd "$(dirname "$0")/.."

what="${1:-all}"

if [ "$what" = "all" ] || [ "$what" = "lua" ]; then
	echo "== luacheck"
	luacheck mods

	echo "== busted"
	busted
fi

if [ "$what" = "all" ] || [ "$what" = "rust" ]; then
	if ! command -v cargo >/dev/null; then
		echo "== rust: cargo not found, skipped" >&2
		exit 1
	fi
	echo "== cargo fmt"
	cargo fmt --all --check

	echo "== cargo clippy"
	cargo clippy --all-targets --quiet -- -D warnings

	echo "== cargo test"
	cargo test --quiet
fi

if [ "$what" = "all" ] || [ "$what" = "frontend" ]; then
	if ! command -v npm >/dev/null; then
		echo "== frontend: npm not found, skipped" >&2
		exit 1
	fi
	cd frontend
	if [ ! -d node_modules ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then
		echo "== npm ci"
		npm ci --silent
	fi

	echo "== generated types"
	npm run --silent types:check

	echo "== eslint"
	npm run --silent lint

	echo "== type check"
	npm run --silent typecheck

	echo "== vitest"
	npm run --silent test

	echo "== build"
	npm run --silent build
	cd ..
fi
