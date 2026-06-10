#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

npx skills add . -g -a cursor --copy -y
echo "Synced GNADD skills to ~/.cursor/skills/"
