#!/usr/bin/env bash
set -euo pipefail

AGENT="${AGENT:-cursor}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

./scripts/build.sh
npx skills add . -g -a "$AGENT" --copy -y
echo "Synced GNADD skills (agent: $AGENT)"
