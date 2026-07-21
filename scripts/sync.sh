#!/usr/bin/env bash
set -euo pipefail

# Author-local sync: rebuild skill copies and install to every agent in
# AGENTS (space-separated; override like AGENTS="cursor" ./scripts/sync.sh).
AGENTS="${AGENTS:-cursor claude-code}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

./scripts/build.sh

read -ra agent_list <<< "$AGENTS"
agent_flags=()
for a in "${agent_list[@]}"; do agent_flags+=(-a "$a"); done

npx skills add . -g "${agent_flags[@]}" --copy -y
echo "Synced GNADD skills (agents: $AGENTS)"
