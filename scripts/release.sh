#!/usr/bin/env bash
# Cut a GNADD release: verify the changelog entry, stamp the version, repin
# the canonical-guide URLs to the release tag, rebuild skill copies, and run
# the tests. Prints the final commit/tag/release commands instead of running
# them — the release commit goes through the normal loop like any other
# change, and the GitHub Release is created after the tag exists.
#
# Usage: scripts/release.sh v0.3.0
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TAG="${1:-}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: scripts/release.sh vX.Y.Z" >&2; exit 1; }
VERSION="${TAG#v}"

# 0. Changelog gate: no release without a written entry for it. When the
#    entry is missing, draft one from the commit history since the last tag
#    (squash-only merges: one commit = one PR title, conventional-commit
#    formatted) grouped into Keep a Changelog headings — the human curates
#    the draft into CHANGELOG.md and re-runs, instead of reconstructing the
#    list by hand. The gate still blocks: drafting never releases.
if ! grep -q "^## \[$VERSION\]" CHANGELOG.md; then
  LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
  RANGE="${LAST_TAG:+$LAST_TAG..}HEAD"
  {
    echo "CHANGELOG.md has no \"## [$VERSION]\" entry."
    echo "Draft below covers every commit on main since ${LAST_TAG:-the first commit} — curate it into CHANGELOG.md, then re-run."
  } >&2
  echo
  echo "## [$VERSION] — $(date +%Y-%m-%d)"
  draft_group() { # <Keep-a-Changelog heading> <subject regex>
    local heading="$1" re="$2" subjects
    subjects="$(git log "$RANGE" --no-merges --pretty='%s' \
      | grep -E "$re" \
      | sed -E 's/^(feat|fix|chore|docs|refactor|test|style|perf)(\([^)]*\))?!?: *//' \
      | sed 's/^/- /' || true)"
    [ -n "$subjects" ] || return 0
    printf '\n### %s\n\n%s\n' "$heading" "$subjects"
  }
  draft_group "Added"   '^feat(\(|!|:)'
  draft_group "Fixed"   '^fix(\(|!|:)'
  draft_group "Changed" '^(chore|docs|refactor|test|style|perf)(\(|!|:)'
  # Catch-all: anything the three groups above did not claim, so the draft
  # provably covers every commit in the range.
  OTHER="$(git log "$RANGE" --no-merges --pretty='%s' \
    | grep -vE '^(feat|fix|chore|docs|refactor|test|style|perf)(\(|!|:)' \
    | sed 's/^/- /' || true)"
  [ -z "$OTHER" ] || printf '\n### Other\n\n%s\n' "$OTHER"
  exit 1
fi

# 1. Stamp the CLI version.
sed -i.bak -E "s/^VERSION=\"[^\"]*\"/VERSION=\"$VERSION\"/" bin/gnadd && rm bin/gnadd.bak

# 2. Repin the canonical guide URLs to the release tag (raw.githubusercontent
#    resolves tag names directly). This is the only sanctioned way to move
#    the pin — see help-gnadd / audit-gnadd.
for f in skills/help-gnadd/SKILL.md skills/audit-gnadd/SKILL.md; do
  sed -i.bak -E \
    "s#raw\.githubusercontent\.com/AlexHagemeister/gnadd/[^/]+/GNADD\.md#raw.githubusercontent.com/AlexHagemeister/gnadd/$TAG/GNADD.md#g" \
    "$f" && rm "$f.bak"
done

# 3. Rebuild skill copies and verify everything still holds.
./scripts/build.sh
bash test/run.sh

echo
echo "Release $TAG prepared. Ship it through the loop:"
echo "  1. review the diff (changelog + version stamp + repinned URLs + skill copies)"
echo "  2. commit:   git commit -am \"chore: release $TAG\""
echo "  3. after the PR merges to main:"
echo "       git tag $TAG <merge-commit> && git push origin $TAG"
echo "  4. publish the GitHub Release with the changelog entry as notes:"
echo "       gh release create $TAG --title \"gnadd $TAG\" --notes \"<the [$VERSION] section of CHANGELOG.md>\""
echo "  5. consumers refresh per help-gnadd's Install & Update: npx skills update -y"
echo "     in the scope they installed with (-g or -p); local checkouts re-run scripts/sync.sh"
