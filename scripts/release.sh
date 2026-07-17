#!/usr/bin/env bash
# Cut a GNADD release: stamp the version, repin the canonical-guide URLs to
# the release tag, rebuild skill copies, and run the tests. Prints the final
# commit/tag/push commands instead of running them — the release commit goes
# through the normal loop like any other change.
#
# Usage: scripts/release.sh v0.2.0
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TAG="${1:-}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: scripts/release.sh vX.Y.Z" >&2; exit 1; }
VERSION="${TAG#v}"

# 1. Stamp the CLI version.
sed -i.bak -E "s/^VERSION=\"[^\"]*\"/VERSION=\"$VERSION\"/" bin/gnadd && rm bin/gnadd.bak

# 2. Repin the canonical guide URLs to the release tag (raw.githubusercontent
#    resolves tag names directly). This is the only sanctioned way to move
#    the pin — see gnadd-context / gnadd-audit.
for f in skills/gnadd-context/SKILL.md skills/gnadd-audit/SKILL.md; do
  sed -i.bak -E \
    "s#raw\.githubusercontent\.com/AlexHagemeister/gnadd/[^/]+/GNADD\.md#raw.githubusercontent.com/AlexHagemeister/gnadd/$TAG/GNADD.md#g" \
    "$f" && rm "$f.bak"
done

# 3. Rebuild skill copies and verify everything still holds.
./scripts/build.sh
bash test/run.sh

echo
echo "Release $TAG prepared. Ship it through the loop:"
echo "  1. review the diff (version stamp + repinned URLs + skill copies)"
echo "  2. commit:   git commit -am \"chore: release $TAG\""
echo "  3. after the PR merges to main:"
echo "       git tag $TAG <merge-commit> && git push origin $TAG"
echo "  4. consumers refresh with: npx skills update -g -y"
