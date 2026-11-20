#!/usr/bin/env bash
# Builds the agent for a server, with the template for worlds inside:
#   scripts/agent-build.sh
# First scripts/template-build.sh packs game and mods, then cargo builds
# the agent and embeds the archive. The result is target/release/lep-agent.
#
# A plain `cargo build --package lep-agent` gives an agent without a
# template. It runs and reports, but cannot create worlds.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"

scripts/template-build.sh
export LEP_TEMPLATE="$repo/target/lep-template/template.tar.gz"
cargo build --release --package lep-agent
echo "Built target/release/lep-agent with the template inside."
