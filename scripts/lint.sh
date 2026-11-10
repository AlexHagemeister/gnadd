#!/usr/bin/env bash
# The one lint definition. CI runs it as its own step, and the full local
# suite (test/run.sh) runs it as the case named lint, so the two cannot drift.
#
# Exit 0: clean. Exit 1: shellcheck found something (its other codes pass
# through). Exit 77: shellcheck is not installed, so nothing was linted.
# 77 is never a pass: CI fails on it, and the local suite reports a skip.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "lint SKIPPED: shellcheck is not installed, so nothing was linted" >&2
  exit 77
fi
exec shellcheck -S warning bin/gnadd scripts/*.sh
