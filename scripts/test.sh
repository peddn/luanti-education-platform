#!/usr/bin/env bash
# Runs all static checks and unit tests: Lua mods and Rust backend.
#   scripts/test.sh          everything
#   scripts/test.sh lua      only the Lua mods
#   scripts/test.sh rust     only the Rust packages
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
