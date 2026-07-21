#!/usr/bin/env bash
# Copy the canonical script (bin/gnadd) into each operational skill as
# gnadd.sh, so installed skills are self-contained wherever the skills CLI
# copies them. bin/gnadd is the single source of truth — never edit the
# copies. test/run.sh fails if they drift.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

for skill in prime-gnadd start-issue-gnadd commit-gnadd resolve-issue-gnadd quickfix-gnadd yolo-gnadd; do
  cp bin/gnadd "skills/$skill/gnadd.sh"
  chmod +x "skills/$skill/gnadd.sh"
done

echo "Synced bin/gnadd into operational skills (prime-gnadd, start-issue-gnadd, commit-gnadd, resolve-issue-gnadd, quickfix-gnadd, yolo-gnadd)"
