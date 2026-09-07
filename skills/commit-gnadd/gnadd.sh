#!/usr/bin/env bash
# gnadd: deterministic mechanics for the GNADD workflow.
#
# Skills call these subcommands instead of improvising raw git. Humans can
# call them too. Every invariant the workflow depends on is enforced here,
# in code, the same way every time:
#
#   - all syncs onto main are fast-forward-only
#   - the dangerous divergence direction (local main ahead of origin) halts
#   - the working tree is protected before any checkout
#   - branch cleanup is gated on GitHub confirming the PR actually merged
#
# When a state needs a human decision, the command prints `state=<NAME>`
# plus context and exits 2. It never guesses, never resets, never forces.
#
# Output convention (stdout, parseable):
#   key=value    facts for the caller
#   note: ...    human-readable context
#   error: ...   what went wrong
# Exit codes: 0 ok, 1 usage/unexpected failure, 2 named state needing a human.

set -euo pipefail

VERSION="0.5.0"
GH="${GNADD_GH:-gh}"
MAIN="${GNADD_MAIN:-main}"

# ---------------------------------------------------------------- helpers

say()  { printf '%s\n' "$*"; }
note() { printf 'note: %s\n' "$*"; }
err()  { printf 'error: %s\n' "$*"; }

die_state() { # die_state NAME message...
  local name="$1"; shift
  say "state=$name"
  [ $# -gt 0 ] && err "$*"
  exit 2
}

usage_die() { err "$*"; exit 1; }

current_branch() { git symbolic-ref --quiet --short HEAD || true; }

tree_dirty() { [ -n "$(git status --porcelain)" ]; }

has_remote() { git remote get-url origin >/dev/null 2>&1; }

fetch_origin() {
  has_remote || { say "remote=none"; return 1; }
  git fetch --prune origin >/dev/null 2>&1 || {
    note "fetch failed (offline?); using last-known remote state"
  }
  return 0
}

# main_ahead / main_behind relative to origin/main. Requires origin/main ref.
main_counts() {
  MAIN_AHEAD=$(git rev-list --count "origin/$MAIN..$MAIN" 2>/dev/null || echo "?")
  MAIN_BEHIND=$(git rev-list --count "$MAIN..origin/$MAIN" 2>/dev/null || echo "?")
}

print_main_state() {
  main_counts
  say "main_ahead=$MAIN_AHEAD"
  say "main_behind=$MAIN_BEHIND"
  if [ "$MAIN_AHEAD" = "?" ]; then
    say "main_state=unknown"
  elif [ "$MAIN_AHEAD" -gt 0 ]; then
    say "main_state=diverged"
  elif [ "$MAIN_BEHIND" -gt 0 ]; then
    say "main_state=behind"
  else
    say "main_state=synced"
  fi
}

show_divergence() {
  note "commits on local $MAIN that origin lacks (the dangerous direction):"
  git log --oneline "origin/$MAIN..$MAIN" | sed 's/^/  /'
  note "commits on origin/$MAIN that local lacks:"
  git log --oneline "$MAIN..origin/$MAIN" | sed 's/^/  /'
}

print_upstream_state() { # upstream= (name or none) and ahead_of_upstream= for the current branch
  local up
  if up="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)"; then
    say "upstream=$up"
    say "ahead_of_upstream=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  else
    # No upstream: nothing on this branch is on GitHub yet, so every commit
    # beyond origin/main counts as unpushed.
    say "upstream=none"
    say "ahead_of_upstream=$(git rev-list --count "origin/$MAIN..HEAD" 2>/dev/null || echo 0)"
  fi
}

railed_push() { # push the current branch to origin, setting upstream; never forces
  # Fast-forward pushes only. If origin has commits this branch lacks, git
  # refuses and the caller halts: a human decides, never a force.
  git push -u origin HEAD >/dev/null 2>&1 || die_state PUSH_FAILED "push to origin failed (network, auth, or the remote branch has commits this one lacks); never force. Check and retry"
  say "pushed=true"
  say "upstream=$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo none)"
}

issue_from_branch() { # sets ISSUE_NUM ("" if not an issue branch)
  local b="$1"
  if [[ "$b" =~ ^issue-([0-9]+)/ ]]; then
    ISSUE_NUM="${BASH_REMATCH[1]}"
  else
    ISSUE_NUM=""
  fi
}

require_clean_tree() {
  if tree_dirty; then
    say "state=DIRTY_TREE"
    err "working tree has uncommitted changes; a human must choose commit/stash/abort first"
    git status --porcelain | sed 's/^/  /'
    exit 2
  fi
}

gh_json() { # gh_json <field> <gh args...>: single field via --jq
  local field="$1"; shift
  "$GH" "$@" --json "$field" --jq ".$field"
}

# ---------------------------------------------------------------- trace
#
# Every subcommand leaves a receipt: one line per invocation (UTC time,
# command, exit status, branch) appended to gnadd-trace.log inside .git/,
# never in the committed tree. The trace turns "did the mechanics go through
# the rails?" from a trust question into a checkable artifact: a run that
# improvised raw git has gaps here. `gnadd trace show|reset` reads/opens it.

TRACE_FILE=""
TRACE_CMD=""

trace_init() {
  local gitdir
  gitdir="$(git rev-parse --git-dir 2>/dev/null)" || return 0
  TRACE_FILE="$gitdir/gnadd-trace.log"
}

trace_on_exit() {
  local status=$?
  trap - EXIT
  # When a run is killed mid-pipe (SIGPIPE), bash 3.2 keeps the stdout it
  # failed to write and flushes that stale buffer into the next redirection
  # or command substitution, i.e. straight into the trace line (issue #38).
  # Drain it to /dev/null first, then build and append the line whole.
  printf '\n' >/dev/null 2>&1 || true
  { [ -n "$TRACE_FILE" ] && [ -n "$TRACE_CMD" ]; } || return 0
  local ts br
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts=""
  br="$(current_branch)"
  printf '%s gnadd %s status=%s branch=%s\n' \
    "$ts" "$TRACE_CMD" "$status" "$br" >> "$TRACE_FILE" 2>/dev/null || true
}

cmd_trace() {
  [ -n "$TRACE_FILE" ] || usage_die "not inside a git repository"
  case "${1:-show}" in
    show)
      if [ -s "$TRACE_FILE" ]; then cat "$TRACE_FILE"; else say "trace=empty"; fi ;;
    reset)
      : > "$TRACE_FILE"
      say "trace=reset" ;;
    *) usage_die "usage: gnadd trace [show|reset]" ;;
  esac
}

# ---------------------------------------------------------------- state

cmd_state() {
  local do_fetch=1
  [ "${1:-}" = "--no-fetch" ] && do_fetch=0

  local br; br="$(current_branch)"
  if [ -n "$br" ]; then
    say "branch=$br"
    say "detached=false"
  else
    say "branch="
    say "detached=true"
  fi

  if tree_dirty; then
    say "tree=dirty"
    say "dirty_files=$(git status --porcelain | wc -l | tr -d ' ')"
  else
    say "tree=clean"
  fi

  say "stashes=$(git stash list | wc -l | tr -d ' ')"

  issue_from_branch "$br"
  say "issue=${ISSUE_NUM:-none}"

  if has_remote; then
    say "remote=origin"
    [ "$do_fetch" = 1 ] && fetch_origin >/dev/null
    [ -n "$br" ] && print_upstream_state
    print_main_state
    if [ "$MAIN_AHEAD" != "?" ] && [ "$MAIN_AHEAD" -gt 0 ]; then
      show_divergence
    fi
  else
    say "remote=none"
  fi
}

# ---------------------------------------------------------------- start

cmd_start() {
  local carry=0 args=()
  for a in "$@"; do
    case "$a" in
      --carry) carry=1 ;;
      *) args+=("$a") ;;
    esac
  done
  [ ${#args[@]} -eq 2 ] || usage_die "usage: gnadd start <issue-number> <slug> [--carry]"
  local n="${args[0]}" slug="${args[1]}"
  [[ "$n" =~ ^[0-9]+$ ]] || usage_die "issue number must be numeric, got: $n"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || usage_die "slug must be kebab-case, got: $slug"

  local target="issue-$n/$slug"
  local existing
  existing="$(git branch --list "issue-$n/*" --format='%(refname:short)' | head -1)"

  if [ "$carry" = 1 ]; then
    # Rescue path: dirty tree on main, no existing branch for this issue.
    # `checkout -b` from main preserves the working tree; nothing can be lost.
    local br; br="$(current_branch)"
    [ "$br" = "$MAIN" ] || die_state NOT_ON_MAIN "--carry is only for rescuing a dirty tree on $MAIN (currently on '$br')"
    [ -z "$existing" ] || die_state CARRY_HAS_EXISTING_BRANCH "branch '$existing' already exists for issue #$n; resuming with a dirty tree needs the supervised stash-carry conversation, not --carry"
    tree_dirty || note "tree is clean; --carry not strictly needed"
    git checkout -b "$target" >/dev/null 2>&1
    say "result=created-carry"
    say "branch=$target"
    note "uncommitted changes carried onto $target; $MAIN was not modified (sync it next time the tree is clean)"
    return 0
  fi

  require_clean_tree

  if [ -z "$existing" ] && fetch_origin >/dev/null; then
    # Fresh clone, same issue: the branch lives on origin but not here.
    local remote_branch
    remote_branch="$(git branch -r --list "origin/issue-$n/*" --format='%(refname:short)' | head -1)"
    if [ -n "$remote_branch" ]; then
      local local_name="${remote_branch#origin/}"
      git checkout --track "$remote_branch" >/dev/null 2>&1 || usage_die "cannot check out $remote_branch"
      say "result=resumed"
      say "branch=$local_name"
      say "upstream=$remote_branch"
      note "branch existed on origin only; checked out tracking $remote_branch"
      return 0
    fi
  fi

  if [ -n "$existing" ]; then
    # Resume. Tree is clean, so the checkout is safe.
    git checkout "$existing" >/dev/null 2>&1
    if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      fetch_origin >/dev/null || true
      if ! git merge --ff-only '@{u}' >/dev/null 2>&1; then
        die_state BRANCH_DIVERGED_FROM_REMOTE "'$existing' and its remote have diverged; do not merge or rebase autonomously. A human decides"
      fi
    fi
    say "result=resumed"
    say "branch=$existing"
    return 0
  fi

  # Fresh start: build on a verified-safe main.
  git checkout "$MAIN" >/dev/null 2>&1 || usage_die "cannot check out $MAIN"
  if fetch_origin >/dev/null; then
    main_counts
    if [ "$MAIN_AHEAD" != "?" ] && [ "$MAIN_AHEAD" -gt 0 ]; then
      say "state=DIVERGED_MAIN"
      err "local $MAIN has commits origin lacks; refusing to build on it"
      show_divergence
      note "run 'gnadd doctor' for the sanctioned recovery path"
      exit 2
    fi
    git merge --ff-only "origin/$MAIN" >/dev/null 2>&1 || \
      die_state FF_REFUSED "fast-forward of $MAIN from origin/$MAIN refused; stop and report. Never merge, rebase, or reset here"
  fi
  git checkout -b "$target" >/dev/null 2>&1
  say "result=created"
  say "branch=$target"
}

# ---------------------------------------------------------------- push

# Checkpoint push: the round trail must cite commits GitHub holds, so every
# checkpoint lands on origin. Rails: never from main/master or detached HEAD,
# never a force. A repo with no remote is reported, not refused.
cmd_push() {
  local br; br="$(current_branch)"
  [ -n "$br" ] || die_state DETACHED_HEAD "cannot push from detached HEAD; commits there belong to no branch"
  if [ "$br" = "$MAIN" ] || [ "$br" = "master" ]; then
    die_state ON_MAIN "never push $br from here: work reaches origin/$MAIN only through a PR"
  fi
  if ! has_remote; then
    say "pushed=false"
    say "upstream=none"
    note "no remote configured; the checkpoint stays local"
    return 0
  fi
  railed_push
  say "branch=$br"
}

# ---------------------------------------------------------------- guard-commit

cmd_guard_commit() {
  local br; br="$(current_branch)"
  [ -n "$br" ] || die_state DETACHED_HEAD "commits in detached HEAD belong to no branch and are easy to lose; create a branch first"
  if [ "$br" = "$MAIN" ] || [ "$br" = "master" ]; then
    die_state ON_MAIN "committing to local $br creates the local-ahead divergence this workflow treats as dangerous; use an issue branch"
  fi
  say "branch=$br"
  issue_from_branch "$br"
  say "issue=${ISSUE_NUM:-none}"
}

# ---------------------------------------------------------------- ship

cmd_ship_push() {
  local any_branch=0
  [ "${1:-}" = "--any-branch" ] && any_branch=1

  local br; br="$(current_branch)"
  [ -n "$br" ] || die_state DETACHED_HEAD "cannot ship from detached HEAD"
  if [ "$br" = "$MAIN" ] || [ "$br" = "master" ]; then
    die_state ON_MAIN "never ship from $br: this would push work straight to origin/$MAIN, bypassing the PR gate"
  fi
  issue_from_branch "$br"
  if [ -z "$ISSUE_NUM" ] && [[ ! "$br" =~ ^quickfix/ ]] && [ "$any_branch" = 0 ]; then
    die_state NOT_ISSUE_BRANCH "'$br' is not an issue-<N>/<slug> or quickfix/<slug> branch; a human must confirm shipping it (then re-run with --any-branch)"
  fi
  require_clean_tree

  fetch_origin >/dev/null || true
  local ahead
  ahead=$(git rev-list --count "origin/$MAIN..HEAD" 2>/dev/null || echo 0)
  [ "$ahead" -gt 0 ] || die_state NOTHING_TO_SHIP "no commits on '$br' beyond origin/$MAIN; nothing to resolve"

  railed_push
  say "branch=$br"
  say "issue=${ISSUE_NUM:-none}"

  # Existing-PR detection: resuming a resolve must not try to create a second PR.
  local pr_state pr_number pr_url
  if pr_state="$(gh_json state pr view 2>/dev/null)"; then
    pr_number="$(gh_json number pr view 2>/dev/null || true)"
    pr_url="$(gh_json url pr view 2>/dev/null || true)"
    say "pr_state=$pr_state"
    say "pr_number=$pr_number"
    say "pr_url=$pr_url"
    if [ "$pr_state" = "OPEN" ]; then
      say "pr_exists=true"
      note "an open PR already exists for this branch; skip creation and go to the merge gate"
    else
      say "pr_exists=false"
      note "a $pr_state PR exists for this branch; surface this to the human before creating a new one"
    fi
  else
    say "pr_exists=false"
  fi
}

cmd_ship_status() {
  local pr="${1:-}"
  [ -n "$pr" ] || usage_die "usage: gnadd ship status <pr-number>"
  local mergeable state
  state="$(gh_json state pr view "$pr" 2>/dev/null)" || die_state PR_NOT_FOUND "no PR #$pr found"
  mergeable="$(gh_json mergeable pr view "$pr" 2>/dev/null || echo UNKNOWN)"
  say "pr_state=$state"
  say "mergeable=$mergeable"
  say "checks=$(checks_summary "$pr")"
  note "checks (ship merge refuses unless every one passes; --no-check overrides):"
  "$GH" pr checks "$pr" 2>&1 | sed 's/^/  /' || true
}

# ---------------------------------------------------------------- CI gate (full loop)
#
# The full loop's merge gate. quickfix has its own (one named check, below);
# this one asks every check GitHub reports to pass. "No checks reported" is
# ambiguous: a workflow that has not started yet looks the same as no CI at
# all, so the presence of a workflow file decides which halt it is.

has_workflow() { # any workflow file in the current tree
  git ls-files '.github/workflows' 2>/dev/null | grep -q .
}

checks_summary() { # checks_summary <pr>: pass | pending | failed | not_started | none
  local pr="$1" checks
  checks="$("$GH" pr checks "$pr" 2>/dev/null || true)"
  if [ -z "$checks" ] || printf '%s' "$checks" | grep -qi '^no checks'; then
    if has_workflow; then echo not_started; else echo none; fi
    return 0
  fi
  local statuses; statuses="$(printf '%s
' "$checks" | awk -F'\t' 'NF >= 2 { print $2 }')"
  if printf '%s
' "$statuses" | grep -qx 'pending'; then echo pending; return 0; fi
  if printf '%s
' "$statuses" | grep -vqxE 'pass|skipping'; then echo failed; return 0; fi
  echo pass
}

checks_gate() { # checks_gate <pr>: halt unless every reported check passed
  local pr="$1" summary
  summary="$(checks_summary "$pr")"
  case "$summary" in
    pass) say "checks=pass" ;;
    not_started) die_state CHECKS_PENDING "PR #$pr has a workflow but no checks reported yet; wait (gh pr checks $pr --watch) and re-run" ;;
    pending) die_state CHECKS_PENDING "checks are still running on PR #$pr; wait (gh pr checks $pr --watch) and re-run" ;;
    failed)
      local failing; failing="$("$GH" pr checks "$pr" 2>/dev/null | awk -F'\t' '$2 != "pass" && $2 != "skipping" { print $1 "=" $2 }' | paste -sd, -)"
      die_state CHECK_FAILED "PR #$pr has a failing check ($failing); a red CI is a stop, not a wave-past" ;;
    none) die_state NO_CHECKS "no CI checks reported for PR #$pr and no workflow in the tree; nothing automated verified it. A human must decide (re-run with --no-check to accept that)" ;;
  esac
}

cmd_ship_merge() {
  local pr="" no_check=0
  for a in "$@"; do
    case "$a" in
      --no-check) no_check=1 ;;
      *) pr="$a" ;;
    esac
  done
  [ -n "$pr" ] || usage_die "usage: gnadd ship merge <pr-number> [--no-check]"
  if [ "$no_check" = 1 ]; then
    note "CI gate explicitly skipped (--no-check); the human owns this decision"
    squash_merge "$pr" none
  else
    squash_merge "$pr" full
  fi
}

squash_merge() { # squash_merge <pr> <gate: full|none>: mergeability, then the CI gate, then the merge
  local pr="$1" gate="${2:-full}"
  local state mergeable
  state="$(gh_json state pr view "$pr" 2>/dev/null)" || die_state PR_NOT_FOUND "no PR #$pr found"
  [ "$state" = "OPEN" ] || die_state PR_NOT_OPEN "PR #$pr is $state, not OPEN"
  mergeable="$(gh_json mergeable pr view "$pr" 2>/dev/null || echo UNKNOWN)"
  case "$mergeable" in
    MERGEABLE) ;;
    CONFLICTING) die_state PR_CONFLICTING "PR #$pr conflicts with $MAIN; hand resolution to the human. Never resolve autonomously" ;;
    *) die_state MERGEABILITY_UNKNOWN "GitHub reports mergeable=$mergeable for PR #$pr; wait and re-run 'gnadd ship status $pr'" ;;
  esac
  [ "$gate" = "none" ] || checks_gate "$pr"
  "$GH" pr merge "$pr" --squash >/dev/null 2>&1 || die_state MERGE_FAILED "gh pr merge failed for PR #$pr; report and stop"
  say "merged=true"
  say "pr_number=$pr"
}

cmd_sync_main() {
  require_clean_tree
  git checkout "$MAIN" >/dev/null 2>&1 || usage_die "cannot check out $MAIN"
  fetch_origin >/dev/null || { say "synced=false"; note "no remote; nothing to sync"; return 0; }
  main_counts
  if [ "$MAIN_AHEAD" != "?" ] && [ "$MAIN_AHEAD" -gt 0 ]; then
    say "state=DIVERGED_MAIN"
    err "local $MAIN has commits origin lacks; will not fast-forward over them"
    show_divergence
    note "run 'gnadd doctor' for the sanctioned recovery path"
    exit 2
  fi
  git merge --ff-only "origin/$MAIN" >/dev/null 2>&1 || \
    die_state FF_REFUSED "fast-forward refused; stop and report. Never retry without --ff-only"
  say "synced=true"
  say "main_commit=$(git rev-parse HEAD)"
}

cmd_cleanup() {
  local pr="${1:-}" branch="${2:-}"
  { [ -n "$pr" ] && [ -n "$branch" ]; } || usage_die "usage: gnadd cleanup <pr-number> <branch>"

  # The merge-state check is what makes the force delete provably
  # non-destructive: if the PR merged, the work is on main via the squash
  # commit, so the branch is genuinely redundant.
  local state merged_at merge_commit
  state="$(gh_json state pr view "$pr" 2>/dev/null)" || die_state PR_NOT_FOUND "no PR #$pr found"
  merged_at="$(gh_json mergedAt pr view "$pr" 2>/dev/null || true)"
  if [ "$state" != "MERGED" ] || [ -z "$merged_at" ] || [ "$merged_at" = "null" ]; then
    die_state NOT_MERGED "PR #$pr is not merged (state=$state); refusing to delete '$branch'"
  fi
  merge_commit="$("$GH" pr view "$pr" --json mergeCommit --jq .mergeCommit.oid 2>/dev/null || true)"

  # The merged check only proves that PR #<pr>'s head landed. It says nothing
  # about <branch> unless <branch> IS that head, so confirm the name matches
  # and that nothing was committed to the branch after the head GitHub merged.
  local head_name head_oid
  head_name="$(gh_json headRefName pr view "$pr" 2>/dev/null || true)"
  head_oid="$(gh_json headRefOid pr view "$pr" 2>/dev/null || true)"
  [ -n "$head_name" ] || die_state BRANCH_MISMATCH "could not read PR #$pr's head branch from GitHub; refusing to delete '$branch'"
  [ "$head_name" = "$branch" ] || die_state BRANCH_MISMATCH "PR #$pr merged branch '$head_name', not '$branch'; refusing to delete a branch the PR did not land"

  local br; br="$(current_branch)"
  [ "$br" != "$branch" ] || die_state ON_TARGET_BRANCH "cannot delete the branch you are standing on; run 'gnadd sync-main' first"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    local tip; tip="$(git rev-parse "refs/heads/$branch")"
    if [ -n "$head_oid" ] && [ "$tip" != "$head_oid" ]; then
      local after; after="$(git rev-list --count "$head_oid..$tip" 2>/dev/null || echo "?")"
      die_state UNMERGED_COMMITS "'$branch' is at $tip but PR #$pr merged $head_oid ($after commit(s) after the merged head); refusing to delete. Push them as a new PR or drop them yourself"
    fi
    git branch -D "$branch" >/dev/null 2>&1
    say "local_deleted=true"
  else
    say "local_deleted=false"
    note "no local branch '$branch'"
  fi

  if has_remote && git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    if git push origin --delete "$branch" >/dev/null 2>&1; then
      say "remote_deleted=true"
    else
      say "remote_deleted=false"
      note "remote delete failed (may have been auto-deleted concurrently)"
    fi
  else
    say "remote_deleted=false"
    note "no remote branch '$branch' (auto-delete-on-merge, or never pushed)"
  fi

  if [ -n "$merge_commit" ]; then
    say "merge_commit=$merge_commit"
    note "revert the whole feature later with: git revert $merge_commit"
  fi
}

# ---------------------------------------------------------------- quickfix
#
# The fast path THROUGH the rails for trivial changes: no issue, but always
# branch → PR → CI → squash merge. The guard is what keeps "no issue, no
# plan" safe: the diff must stay glanceable (size cap) and must never touch
# the safety machinery itself (protected paths). Those changes take the
# full loop where a spec and a plan exist.

QF_MAX_FILES="${GNADD_QF_MAX_FILES:-3}"
QF_MAX_LINES="${GNADD_QF_MAX_LINES:-30}"
QF_CHECK="${GNADD_QF_CHECK:-test}"

cmd_quickfix_start() {
  local carry=0 args=()
  for a in "$@"; do
    case "$a" in
      --carry) carry=1 ;;
      *) args+=("$a") ;;
    esac
  done
  [ ${#args[@]} -eq 1 ] || usage_die "usage: gnadd quickfix start <slug> [--carry]"
  local slug="${args[0]}"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] || usage_die "slug must be kebab-case, got: $slug"

  local target="quickfix/$slug"
  git show-ref --verify --quiet "refs/heads/$target" && \
    die_state QF_BRANCH_EXISTS "branch '$target' already exists; pick another slug or finish/clean up that quickfix first"

  if [ "$carry" = 1 ]; then
    # Same lossless rescue as issue start: dirty tree on main, checkout -b
    # preserves the working tree, main is never modified.
    local br; br="$(current_branch)"
    [ "$br" = "$MAIN" ] || die_state NOT_ON_MAIN "--carry is only for rescuing a dirty tree on $MAIN (currently on '$br')"
    tree_dirty || note "tree is clean; --carry not strictly needed"
    git checkout -b "$target" >/dev/null 2>&1
    say "result=created-carry"
    say "branch=$target"
    note "uncommitted changes carried onto $target; $MAIN was not modified"
    return 0
  fi

  require_clean_tree
  git checkout "$MAIN" >/dev/null 2>&1 || usage_die "cannot check out $MAIN"
  if fetch_origin >/dev/null; then
    main_counts
    if [ "$MAIN_AHEAD" != "?" ] && [ "$MAIN_AHEAD" -gt 0 ]; then
      say "state=DIVERGED_MAIN"
      err "local $MAIN has commits origin lacks; refusing to build on it"
      show_divergence
      note "run 'gnadd doctor' for the sanctioned recovery path"
      exit 2
    fi
    git merge --ff-only "origin/$MAIN" >/dev/null 2>&1 || \
      die_state FF_REFUSED "fast-forward of $MAIN from origin/$MAIN refused; stop and report. Never merge, rebase, or reset here"
  fi
  git checkout -b "$target" >/dev/null 2>&1
  say "result=created"
  say "branch=$target"
}

cmd_quickfix_guard() {
  # Scope: everything this quickfix would land: commits beyond origin/main
  # plus any uncommitted changes. Binary files count toward the file cap.
  local base="origin/$MAIN"
  git rev-parse --verify --quiet "$base" >/dev/null || base="$MAIN"

  local files
  files="$( { git diff --name-only "$base...HEAD" 2>/dev/null; git diff --name-only HEAD 2>/dev/null; } | sort -u | sed '/^$/d' )"
  local file_count
  file_count="$(printf '%s' "$files" | grep -c . || true)"

  # A newly added VISION.md is exempt from the line budget: it is the intent
  # document vision-gnadd writes, touches no code, and any real one is longer
  # than the budget. Editing an existing VISION.md stays under the budget.
  local exempt=""
  if { git diff --name-status "$base...HEAD" 2>/dev/null; git diff --name-status HEAD 2>/dev/null; } | grep -qE '^A[[:space:]]+VISION\.md$'; then
    exempt="VISION.md"
  fi

  local lines
  lines="$( { git diff --numstat "$base...HEAD" 2>/dev/null; git diff --numstat HEAD 2>/dev/null; } | \
    awk -v ex="$exempt" '$3 == ex && ex != "" { next } { if ($1 != "-") s += $1; if ($2 != "-") s += $2 } END { print s+0 }' )"

  say "files=$file_count"
  say "lines=$lines"
  [ -n "$exempt" ] && say "exempt=$exempt (new intent document, not counted toward the line budget)"

  [ "$file_count" -gt 0 ] || die_state QF_NOTHING_TO_GUARD "no changes vs $base; nothing to quickfix"

  local protected
  protected="$(printf '%s\n' "$files" | grep -E '^(bin/|scripts/|\.github/)|(^|/)gnadd\.sh$' || true)"
  if [ -n "$protected" ]; then
    say "state=PROTECTED_PATH"
    err "quickfix must never modify the safety machinery it depends on; these paths take the full loop:"
    printf '%s\n' "$protected" | sed 's/^/  /'
    exit 2
  fi

  if [ "$file_count" -gt "$QF_MAX_FILES" ] || [ "$lines" -gt "$QF_MAX_LINES" ]; then
    say "state=TOO_BIG"
    err "change exceeds the quickfix budget (${file_count} files / ${lines} lines vs max ${QF_MAX_FILES}/${QF_MAX_LINES}); use the full loop (new-issue → start-issue)"
    exit 2
  fi

  say "guard=ok"
}

cmd_quickfix_ship() {
  local br; br="$(current_branch)"
  [ -n "$br" ] || die_state DETACHED_HEAD "cannot ship from detached HEAD"
  [[ "$br" =~ ^quickfix/ ]] || die_state NOT_QUICKFIX_BRANCH "'$br' is not a quickfix/<slug> branch"
  require_clean_tree
  cmd_quickfix_guard
  cmd_ship_push --any-branch
}

cmd_quickfix_merge() {
  # Squash-merge only when the PR is OPEN, MERGEABLE, and the CI check has
  # passed. This is the "merges only after CI passes" guarantee, enforced at
  # merge time regardless of what the caller watched or skipped.
  local pr="" check="$QF_CHECK" no_check=0 prev=""
  for a in "$@"; do
    case "$a" in
      --no-check) no_check=1 ;;
      --check) ;;
      *) if [ "$prev" = "--check" ]; then check="$a"; else pr="$a"; fi ;;
    esac
    prev="$a"
  done
  [ -n "$pr" ] || usage_die "usage: gnadd quickfix merge <pr-number> [--check <name>] [--no-check]"

  if [ "$no_check" = 1 ]; then
    note "CI gate explicitly skipped (--no-check); the human owns this decision"
  else
    local checks row status
    checks="$("$GH" pr checks "$pr" 2>/dev/null || true)"
    if [ -z "$checks" ] || printf '%s' "$checks" | grep -qi '^no checks'; then
      die_state QF_NO_CHECKS "no CI checks reported for PR #$pr; nothing automated verified it. A human must decide (re-run with --no-check to accept that)"
    fi
    row="$(printf '%s\n' "$checks" | awk -F'\t' -v c="$check" '$1 == c { print; exit }')"
    [ -n "$row" ] || die_state QF_CHECK_NOT_FOUND "check '$check' not found on PR #$pr; available checks are informational. Pick one with --check <name> or use --no-check deliberately"
    status="$(printf '%s\n' "$row" | awk -F'\t' '{ print $2 }')"
    case "$status" in
      pass) say "check=$check"; say "check_status=pass" ;;
      pending) die_state QF_CHECKS_PENDING "check '$check' is still running on PR #$pr; wait (gh pr checks $pr --watch) and re-run" ;;
      *) die_state QF_CHECK_FAILED "check '$check' reports '$status' on PR #$pr; a failing CI gate is a stop, not a wave-past" ;;
    esac
  fi

  squash_merge "$pr" none
}

cmd_doctor() {
  local rescue_name=""
  if [ "${1:-}" = "--rescue-main" ]; then
    rescue_name="${2:-}"
    [ -n "$rescue_name" ] || usage_die "usage: gnadd doctor --rescue-main <new-branch-name>"
  fi

  if [ -n "$rescue_name" ]; then
    doctor_rescue_main "$rescue_name"
    return $?
  fi

  local findings=0
  local br; br="$(current_branch)"

  if [ -z "$br" ]; then
    findings=$((findings+1))
    say "finding=DETACHED_HEAD"
    note "recipe: git switch -c rescue/<desc>  (turns the detached commits into a real branch; nothing is lost)"
  fi

  if has_remote; then
    fetch_origin >/dev/null
    main_counts
    if [ "$MAIN_AHEAD" != "?" ] && [ "$MAIN_AHEAD" -gt 0 ]; then
      findings=$((findings+1))
      say "finding=DIVERGED_MAIN"
      show_divergence
      note "recipe: gnadd doctor --rescue-main rescue/<desc>"
      note "  moves the stray commits to a rescue branch (lossless), realigns $MAIN to origin/$MAIN"
      note "  without any reset, and leaves you on the rescue branch to route through a PR"
    fi
  fi

  if [ "$br" = "$MAIN" ] && tree_dirty; then
    findings=$((findings+1))
    say "finding=DIRTY_TREE_ON_MAIN"
    note "recipe: /start-issue-gnadd carries these changes onto a fresh issue branch losslessly"
  fi

  local stashes; stashes=$(git stash list | wc -l | tr -d ' ')
  if [ "$stashes" -gt 0 ]; then
    findings=$((findings+1))
    say "finding=STASHES"
    git stash list | sed 's/^/  /'
    note "recipe: git stash branch rescue/<desc>  (materializes the newest stash as a visible branch)"
  fi

  # Issue branches whose work already landed (0 commits beyond main) are
  # likely leftovers from an interrupted cleanup.
  while IFS= read -r ib; do
    [ -n "$ib" ] || continue
    [ "$ib" = "$br" ] && continue
    local extra
    extra=$(git rev-list --count "$MAIN..$ib" 2>/dev/null || echo "?")
    if [ "$extra" = "0" ]; then
      findings=$((findings+1))
      say "finding=STALE_ISSUE_BRANCH"
      note "'$ib' has no commits beyond $MAIN; if its PR merged, clean up with: gnadd cleanup <pr> $ib"
    fi
  done < <(git branch --list 'issue-*' 'quickfix/*' --format='%(refname:short)')

  if [ "$findings" = 0 ]; then
    say "findings=0"
    note "no known bad states detected"
  else
    say "findings=$findings"
  fi
}

doctor_rescue_main() {
  local rescue="$1"
  has_remote || die_state NO_REMOTE "rescue-main needs origin to realign against"
  fetch_origin >/dev/null
  main_counts
  [ "$MAIN_AHEAD" != "?" ] || die_state NO_ORIGIN_MAIN "origin/$MAIN not found"
  [ "$MAIN_AHEAD" -gt 0 ] || die_state NOT_DIVERGED "local $MAIN is not ahead of origin/$MAIN; nothing to rescue"
  git show-ref --verify --quiet "refs/heads/$rescue" && die_state RESCUE_EXISTS "branch '$rescue' already exists; pick another name"

  # Lossless by construction, and never uses reset:
  #   1. bookmark the stray commits on a rescue branch
  #   2. step onto it (same commit as main, so the working tree does not change)
  #   3. move the main ref back to origin/main with branch -f (main is no
  #      longer checked out, so this touches no files)
  git branch "$rescue" "$MAIN" >/dev/null 2>&1
  [ "$(git rev-parse "$rescue")" = "$(git rev-parse "$MAIN")" ] || die_state RESCUE_FAILED "rescue branch does not match $MAIN; aborting before touching anything"
  git checkout "$rescue" >/dev/null 2>&1
  git branch -f "$MAIN" "origin/$MAIN" >/dev/null 2>&1
  [ "$(git rev-parse "$MAIN")" = "$(git rev-parse "origin/$MAIN")" ] || die_state REALIGN_FAILED "$MAIN does not match origin/$MAIN after realign; inspect manually"

  say "rescued=true"
  say "rescue_branch=$rescue"
  say "main_commit=$(git rev-parse "$MAIN")"
  note "stray commits preserved on '$rescue'; you are standing on it"
  note "route them through the loop: open an issue, rename or PR this branch. Never push them to $MAIN directly"
}

# ---------------------------------------------------------------- test

cmd_test() {
  if [ -f package.json ] && grep -q '"test"' package.json; then
    say "runner=npm"
    npm test
  elif [ -f Makefile ] && grep -qE '^test:' Makefile; then
    say "runner=make"
    make test
  elif [ -f Cargo.toml ]; then
    say "runner=cargo"
    cargo test
  elif [ -f go.mod ]; then
    say "runner=go"
    go test ./...
  elif { [ -f pyproject.toml ] || [ -f pytest.ini ] || [ -d tests ]; } && command -v pytest >/dev/null 2>&1; then
    say "runner=pytest"
    pytest
  elif [ -f test/run.sh ]; then
    say "runner=test/run.sh"
    bash test/run.sh
  else
    say "runner=none"
    say "state=NO_TESTS"
    note "no test command detected; the diff review is the only safeguard"
    return 0
  fi
}

# ---------------------------------------------------------------- init

cmd_init() {
  local strict=0 ci=0
  for a in "$@"; do
    case "$a" in
      --strict) strict=1 ;;
      --ci) ci=1 ;;
      *) usage_die "unknown init flag: $a" ;;
    esac
  done

  "$GH" auth status >/dev/null 2>&1 || die_state GH_UNAUTHENTICATED "run 'gh auth login' first"

  local repo
  repo="$("$GH" repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || die_state NO_REPO "not inside a GitHub repo gh can see"
  say "repo=$repo"

  # Merge policy: squash-only, PR body becomes the squash commit message
  # (the decision record lands in git history itself), branches auto-delete.
  # gh has no --squash-merge-commit-title flag; pr-title-description sets
  # the pair (title = PR title, message = PR body) in one go.
  if "$GH" repo edit \
      --enable-squash-merge \
      --enable-merge-commit=false \
      --enable-rebase-merge=false \
      --delete-branch-on-merge \
      --squash-merge-commit-message pr-title-description >/dev/null 2>&1; then
    say "merge_policy=squash-only"
  else
    say "merge_policy=failed"
    note "gh repo edit failed; set squash-only + delete-branch-on-merge + squash message 'pull request title and description' in repo Settings > General > Pull Requests"
  fi

  # Ruleset on main: require a PR, block force pushes and deletion.
  # Default keeps an admin bypass (solo escape hatch); --strict removes it.
  local existing
  existing="$("$GH" api "repos/$repo/rulesets" --jq '.[].name' 2>/dev/null | grep -cx 'gnadd-main' || true)"
  if [ "$existing" != "0" ]; then
    say "ruleset=exists"
  else
    local bypass='[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]'
    [ "$strict" = 1 ] && bypass='[]'
    local ruleset_err; ruleset_err="$(mktemp)"
    if "$GH" api -X POST "repos/$repo/rulesets" --input - >/dev/null 2>"$ruleset_err" <<RULESET
{
  "name": "gnadd-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      } },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ],
  "bypass_actors": $bypass
}
RULESET
    then
      say "ruleset=created"
      [ "$strict" = 1 ] && note "strict mode: no bypass. Even admins must go through PRs"
    else
      say "ruleset=failed"
      # The cause decides what to tell the user (a 403 "Upgrade to GitHub Pro
      # or make this repository public" means rulesets are unavailable on a
      # private free-plan repo), so the first line of gh's error is part of
      # the report, not swallowed.
      say "ruleset_error=$(grep -m1 . "$ruleset_err" 2>/dev/null || echo unknown)"
      note "could not create the ruleset via gh api; add one in repo Settings > Rules (require PR, block force pushes and deletion on $MAIN)"
    fi
    rm -f "$ruleset_err"
  fi

  if [ "$ci" = 1 ]; then
    if [ -f .github/workflows/gnadd-ci.yml ]; then
      say "ci=exists"
    else
      mkdir -p .github/workflows
      cat > .github/workflows/gnadd-ci.yml <<'YAML'
name: tests
on:
  pull_request:
  push:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run project tests
        run: |
          if [ -f package.json ] && grep -q '"test"' package.json; then npm ci && npm test
          elif [ -f Makefile ] && grep -qE '^test:' Makefile; then make test
          elif [ -f Cargo.toml ]; then cargo test
          elif [ -f go.mod ]; then go test ./...
          elif [ -f pyproject.toml ] || [ -f pytest.ini ]; then pip install -e . pytest && pytest
          elif [ -f test/run.sh ]; then bash test/run.sh
          else echo "no test command detected"; fi
YAML
      say "ci=created"
    fi
  fi
  init_report_uncommitted
}

# init's own files. Written to the working tree by `init --ci` and
# `conventions`, landed on main by `init land`. Every command that writes
# one of them ends by reporting which are not yet committed, so the report
# has a slot for the leftover instead of leaving it for the next quickfix
# to trip over.
INIT_PATHS="AGENTS.md .github/workflows/gnadd-ci.yml"

init_uncommitted() { # init's paths that are untracked or modified, one per line
  local p
  for p in $INIT_PATHS; do
    [ -e "$p" ] || continue
    if ! git ls-files --error-unmatch "$p" >/dev/null 2>&1 || ! git diff --quiet HEAD -- "$p" 2>/dev/null; then
      printf '%s\n' "$p"
    fi
  done
}

init_report_uncommitted() {
  local u; u="$(init_uncommitted | paste -sd, -)"
  say "uncommitted=${u:-none}"
  [ -n "$u" ] && note "land these on $MAIN with 'gnadd init land' (no issue needed; the PR is the record)"
  return 0
}

cmd_init_land() {
  # Land init's own files through the rails: a quickfix branch carrying them,
  # one commit, a push, and a PR. The merge stays with 'ship merge' so the
  # CI gate (which the workflow file itself may have just created) decides.
  # Nothing here touches local main: the branch is checked out from it with
  # the working tree intact, the same lossless rescue quickfix --carry uses.
  local br; br="$(current_branch)"
  [ "$br" = "$MAIN" ] || die_state NOT_ON_MAIN "init land starts from $MAIN (currently on '$br'); its files were written there"

  local files; files="$(init_uncommitted)"
  if [ -z "$files" ]; then
    say "landed=none"
    note "no init files are uncommitted; nothing to land"
    return 0
  fi

  # Only init's files may ride on this PR. Anything else in the tree is the
  # user's work, which has its own route (an issue, or quickfix) and must not
  # be swept into a PR labeled as init's.
  local foreign
  foreign="$(git status --porcelain --untracked-files=all | awk '{ print $NF }' | grep -vxF -f <(printf '%s\n' "$files") || true)"
  if [ -n "$foreign" ]; then
    say "state=INIT_LAND_FOREIGN_FILES"
    err "the tree holds changes that are not init's; commit or land them first, then re-run:"
    printf '%s\n' "$foreign" | sed 's/^/  /'
    exit 2
  fi

  if fetch_origin >/dev/null; then
    main_counts
    if [ "$MAIN_AHEAD" != "?" ] && [ "$MAIN_AHEAD" -gt 0 ]; then
      say "state=DIVERGED_MAIN"
      err "local $MAIN has commits origin lacks; refusing to build on it"
      show_divergence
      note "run 'gnadd doctor' for the sanctioned recovery path"
      exit 2
    fi
  fi

  local target="quickfix/gnadd-init"
  git show-ref --verify --quiet "refs/heads/$target" && \
    die_state QF_BRANCH_EXISTS "branch '$target' already exists; finish or clean up that landing first (gnadd cleanup <pr> $target)"
  git checkout -b "$target" >/dev/null 2>&1

  local list; list="$(printf '%s\n' "$files" | paste -sd, -)"
  # shellcheck disable=SC2086
  git add -- $files
  git commit -q -m "chore: land the GNADD init files" -m "Files: $list

Written by gnadd init and gnadd conventions. Quickfix: no issue; this PR
is the record." >/dev/null
  railed_push

  local pr_url pr_number
  pr_url="$("$GH" pr create --title "chore: land the GNADD init files" --body "Files: $list

Written by \`gnadd init\` and \`gnadd conventions\`: the conventions file that
points agents at GNADD, and the CI workflow when one was requested.

Quickfix: no issue; this PR is the record. Landed by \`gnadd init land\`." 2>/dev/null | grep -m1 -E '^https?://' || true)"
  [ -n "$pr_url" ] || die_state PR_CREATE_FAILED "commit and push landed on '$target' but gh pr create failed; create the PR by hand (gh pr create) and continue with ship merge"
  pr_number="${pr_url##*/}"
  say "branch=$target"
  say "files=$list"
  say "pr_number=$pr_number"
  say "pr_url=$pr_url"
  note "next: 'gnadd ship merge $pr_number' once checks pass (--no-check when the repo has no CI), then 'gnadd sync-main' and 'gnadd cleanup $pr_number $target'"
}

# ---------------------------------------------------------------- round
#
# A round is one build/try/feedback cycle on an issue branch. Each checkpoint
# posts one append-only comment on the issue: which round, what changed, and
# the user's feedback that drove it. The trail survives the squash merge and
# is what a later session reads to resume. The round number comes from the
# record (existing round comments on the issue), never from memory.

ROUND_MARKER="<!-- gnadd:round -->"

round_issue_or_die() { # sets ISSUE_NUM from the branch; halts elsewhere
  local br; br="$(current_branch)"
  [ -n "$br" ] || die_state DETACHED_HEAD "round comments belong to an issue branch; detached HEAD has none"
  issue_from_branch "$br"
  [ -n "$ISSUE_NUM" ] || die_state NOT_ISSUE_BRANCH "round comments are posted only from issue-<N>/* branches (on: $br)"
  ROUND_BRANCH="$br"
}

round_count() { # round_count <issue>: number of existing round comments
  "$GH" api "repos/{owner}/{repo}/issues/$1/comments" --paginate \
    --jq "[.[] | select(.body | contains(\"$ROUND_MARKER\"))] | length" 2>/dev/null \
    | awk '{s+=$1} END {print s+0}'
}

cmd_round_post() {
  local changed="" feedback="" feedback_file="" no_feedback="" have_fb=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --changed)       changed="${2:-}"; shift ;;
      --feedback)      feedback="${2:-}"; have_fb=$((have_fb+1)); shift ;;
      --feedback-file) feedback_file="${2:-}"; have_fb=$((have_fb+1)); shift ;;
      --no-feedback)   no_feedback="${2:-}"; have_fb=$((have_fb+1)); shift ;;
      *) usage_die "usage: gnadd round post --changed <text> (--feedback <text> | --feedback-file <path> | --no-feedback <reason>)" ;;
    esac
    shift
  done
  round_issue_or_die
  [ -n "$changed" ] || usage_die "round post needs --changed <text>: what this checkpoint changed, in one or two lines"
  [ "$have_fb" -eq 1 ] || usage_die "round post needs exactly one of --feedback, --feedback-file, or --no-feedback <reason>; feedback is never inferred"
  if [ -n "$feedback_file" ]; then
    [ -s "$feedback_file" ] || usage_die "feedback file is missing or empty: $feedback_file (use --no-feedback <reason> when the user said nothing this round)"
    feedback="$(cat "$feedback_file")"
  fi
  if [ -z "$no_feedback" ] && [ -z "$feedback" ]; then
    usage_die "feedback text is empty; pass the user's words as typed, or --no-feedback <reason> to record that there were none"
  fi

  # The comment cites a sha, so the sha must be on GitHub before the comment is.
  cmd_push

  local n; n="$(round_count "$ISSUE_NUM")"
  local round=$((n+1))
  local sha; sha="$(git rev-parse --short HEAD)"
  local body; body="$(mktemp)"
  {
    printf '%s\n' "$ROUND_MARKER"
    printf '## Round %s\n\n' "$round"
    printf 'Commit: `%s` on `%s`\n\n' "$sha" "$ROUND_BRANCH"
    printf '**Changed:** %s\n\n' "$changed"
    if [ -n "$no_feedback" ]; then
      printf '**Feedback:** none this round (%s).\n' "$no_feedback"
    else
      printf '**Feedback** (transcribed by the agent from chat, the user'"'"'s words as typed):\n\n'
      printf '%s\n' "$feedback" | sed 's/^/> /'
    fi
  } > "$body"
  if ! "$GH" issue comment "$ISSUE_NUM" --body-file "$body" >/dev/null; then
    rm -f "$body"
    die_state COMMENT_FAILED "could not post the round comment on issue #$ISSUE_NUM (network? auth?); the commit is safe, re-run round post"
  fi
  rm -f "$body"
  say "issue=$ISSUE_NUM"
  say "round=$round"
  say "posted=true"
}

cmd_round_list() {
  local issue="${1:-}"
  if [ -z "$issue" ]; then
    round_issue_or_die
    issue="$ISSUE_NUM"
  fi
  local n; n="$(round_count "$issue")"
  say "issue=$issue"
  say "rounds=$n"
  [ "$n" -gt 0 ] || return 0
  "$GH" api "repos/{owner}/{repo}/issues/$issue/comments" --paginate \
    --jq ".[] | select(.body | contains(\"$ROUND_MARKER\")) | .body" \
    | grep -v -F "$ROUND_MARKER" | sed 's/^/  /'
}

# ---------------------------------------------------------------- phase
#
# A phase is the project's current development stage, held as one open
# GitHub milestone. Its description says what the phase is trying to find
# out and what ends it. Issues attach to it. Phase state lives in the system
# of record, changes only by the human's act (open, close with a verdict),
# and never carries a due date. The agent may propose closing; it never does.

json_str() { # json_str <text>: JSON string literal (quotes, backslashes, newlines)
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS=""} NR>1{printf "\\n"} {print}'
}

phase_rows() { # tab rows: number, title, open_issues, closed_issues, description (flattened)
  "$GH" api "repos/{owner}/{repo}/milestones?state=open&per_page=100" \
    --jq '.[] | "\(.number)\t\(.title)\t\(.open_issues)\t\(.closed_issues)\t\(.description // "" | gsub("\n"; " "))"' 2>/dev/null || true
}

phase_count() {
  "$GH" api "repos/{owner}/{repo}/milestones?state=open&per_page=100" --jq 'length' 2>/dev/null | awk '{s+=$1} END {print s+0}'
}

cmd_phase_status() {
  local n; n="$(phase_count)"
  if [ "$n" -eq 0 ]; then
    say "phase=none"
    return 0
  fi
  phase_rows | while IFS="$(printf '\t')" read -r num title oi ci desc; do
    say "phase=$title"
    say "phase_number=$num"
    say "open_issues=$oi"
    say "closed_issues=$ci"
    say "description=$desc"
  done
  if [ "$n" -gt 1 ]; then
    note "$n milestones are open; the phase rule wants exactly one (close the others with a verdict, or treat the first as the phase)"
  fi
  return 0
}

cmd_phase_open() {
  local title="" desc="" desc_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --description)      desc="${2:-}"; shift ;;
      --description-file) desc_file="${2:-}"; shift ;;
      -*) usage_die "usage: gnadd phase open <title> (--description <text> | --description-file <path>)" ;;
      *)  [ -z "$title" ] && title="$1" || usage_die "phase open takes one title" ;;
    esac
    shift
  done
  [ -n "$title" ] || usage_die "phase open needs a title"
  [ -n "$desc_file" ] && desc="$(cat "$desc_file")"
  [ -n "$desc" ] || usage_die "phase open needs --description: what this phase is trying to find out, and what ends it"
  local n; n="$(phase_count)"
  if [ "$n" -gt 0 ]; then
    say "state=PHASE_OPEN"
    err "a phase is already open; one open phase at a time, close it with a verdict first:"
    phase_rows | cut -f2 | sed 's/^/  /'
    exit 2
  fi
  local out
  out="$("$GH" api -X POST "repos/{owner}/{repo}/milestones" --input - \
          --jq '"\(.number)\t\(.html_url)"' <<JSON
{"title": "$(json_str "$title")", "description": "$(json_str "$desc")", "state": "open"}
JSON
  )" || die_state PHASE_CREATE_FAILED "could not create milestone '$title' (network? auth? permissions?)"
  say "phase=$title"
  say "phase_number=$(printf '%s' "$out" | cut -f1)"
  say "url=$(printf '%s' "$out" | cut -f2)"
  say "opened=true"
}

cmd_phase_close() {
  local title="" verdict="" verdict_file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --verdict)      verdict="${2:-}"; shift ;;
      --verdict-file) verdict_file="${2:-}"; shift ;;
      -*) usage_die "usage: gnadd phase close <title> (--verdict <text> | --verdict-file <path>)" ;;
      *)  [ -z "$title" ] && title="$1" || usage_die "phase close takes one title" ;;
    esac
    shift
  done
  [ -n "$title" ] || usage_die "phase close needs the open phase's title"
  [ -n "$verdict_file" ] && verdict="$(cat "$verdict_file")"
  [ -n "$verdict" ] || usage_die "phase close needs --verdict: what this phase found out, in the user's words; closing is the human's act"
  local num
  num="$(phase_rows | awk -F'\t' -v t="$title" '$2 == t {print $1; exit}')"
  [ -n "$num" ] || die_state PHASE_NOT_FOUND "no open milestone titled '$title' (gnadd phase status lists the open ones)"
  local desc
  desc="$("$GH" api "repos/{owner}/{repo}/milestones/$num" --jq '.description // ""' 2>/dev/null || true)"
  local newdesc
  newdesc="$(printf '%s\n\n## Verdict\n\n%s' "$desc" "$verdict")"
  "$GH" api -X PATCH "repos/{owner}/{repo}/milestones/$num" --input - >/dev/null <<JSON || die_state PHASE_CLOSE_FAILED "could not close milestone '$title'"
{"state": "closed", "description": "$(json_str "$newdesc")"}
JSON
  say "phase=$title"
  say "phase_number=$num"
  say "closed=true"
}

# ---------------------------------------------------------------- conventions
#
# The conventions file (AGENTS.md, agent-agnostic) is the one file an agent
# loads at session start. It points at GNADD and carries the single project
# fact the round loop needs: the preview launch line. It holds no task state
# and nothing an agent must keep updated. Writes are idempotent: rerunning
# changes only a preview line that actually differs, and never touches text
# outside the marked block.

CONV_FILE="AGENTS.md"
CONV_START="<!-- gnadd:conventions -->"
CONV_END="<!-- /gnadd:conventions -->"
CONV_PLACEHOLDER="(none yet: put the command or URL that starts a dev preview here)"

conventions_block() { # conventions_block <preview>
  cat <<BLOCK
$CONV_START
## GNADD

This repo runs GNADD (Git-Native Agent-Driven Development): GitHub issues,
branches, PRs, and git history are the sole system of record. No task files,
no progress notes. Start every session with \`/prime-gnadd\`. Every change
lands through an issue, a branch, and a PR, or through \`/quickfix-gnadd\` for
a trivial one. Project intent lives in \`VISION.md\` when present.

Preview launch: ${1:-$CONV_PLACEHOLDER}
$CONV_END
BLOCK
}

cmd_conventions() {
  local preview=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --preview) preview="${2:-}"; shift ;;
      *) usage_die "usage: gnadd conventions [--preview <command or URL>]" ;;
    esac
    shift
  done
  git rev-parse --show-toplevel >/dev/null 2>&1 || die_state NO_REPO "not inside a git repository"
  local f; f="$(git rev-parse --show-toplevel)/$CONV_FILE"
  if [ ! -f "$f" ]; then
    conventions_block "$preview" > "$f"
    say "conventions=created"
  elif ! grep -qF "$CONV_START" "$f"; then
    { printf '\n'; conventions_block "$preview"; } >> "$f"
    say "conventions=updated"
    note "GNADD block appended to the existing $CONV_FILE; nothing else in it was touched"
  else
    local current
    current="$(sed -n 's/^Preview launch: //p' "$f" | head -1)"
    if [ -n "$preview" ] && [ "$current" != "$preview" ]; then
      local tmp; tmp="$(mktemp)"
      awk -v p="$preview" 'BEGIN{done=0} /^Preview launch: / && !done {print "Preview launch: " p; done=1; next} {print}' "$f" > "$tmp"
      mv "$tmp" "$f"
      say "conventions=updated"
      note "preview launch line changed from '$current'"
    else
      say "conventions=unchanged"
    fi
  fi
  say "file=$CONV_FILE"
  say "preview=$(sed -n 's/^Preview launch: //p' "$f" | head -1)"
  init_report_uncommitted
}

# ---------------------------------------------------------------- dispatch

main() {
  local cmd="${1:-}"
  shift || true
  trace_init
  case "$cmd" in
    trace|version|--version|"") ;;  # meta commands leave no trace lines
    *) TRACE_CMD="$cmd${*:+ $*}"; trap trace_on_exit EXIT ;;
  esac
  case "$cmd" in
    state)        cmd_state "$@" ;;
    start)        cmd_start "$@" ;;
    push)         cmd_push "$@" ;;
    guard-commit) cmd_guard_commit "$@" ;;
    ship)
      local sub="${1:-}"; shift || true
      case "$sub" in
        push)   cmd_ship_push "$@" ;;
        status) cmd_ship_status "$@" ;;
        merge)  cmd_ship_merge "$@" ;;
        *) usage_die "usage: gnadd ship {push|status|merge} ..." ;;
      esac ;;
    quickfix)
      local qsub="${1:-}"; shift || true
      case "$qsub" in
        start) cmd_quickfix_start "$@" ;;
        guard) cmd_quickfix_guard "$@" ;;
        ship)  cmd_quickfix_ship "$@" ;;
        merge) cmd_quickfix_merge "$@" ;;
        *) usage_die "usage: gnadd quickfix {start|guard|ship|merge} ..." ;;
      esac ;;
    round)
      local rsub="${1:-}"; shift || true
      case "$rsub" in
        post) cmd_round_post "$@" ;;
        list) cmd_round_list "$@" ;;
        *) usage_die "usage: gnadd round {post|list} ..." ;;
      esac ;;
    phase)
      local psub="${1:-}"; shift || true
      case "$psub" in
        status) cmd_phase_status "$@" ;;
        open)   cmd_phase_open "$@" ;;
        close)  cmd_phase_close "$@" ;;
        *) usage_die "usage: gnadd phase {status|open|close} ..." ;;
      esac ;;
    sync-main)    cmd_sync_main "$@" ;;
    cleanup)      cmd_cleanup "$@" ;;
    doctor)       cmd_doctor "$@" ;;
    test)         cmd_test "$@" ;;
    init)
      if [ "${1:-}" = "land" ]; then shift; cmd_init_land "$@"; else cmd_init "$@"; fi ;;
    conventions)  cmd_conventions "$@" ;;
    trace)        cmd_trace "$@" ;;
    version|--version)
      # VERSION is stamped by scripts/release.sh at release time, but installs
      # track the default branch, so a copy may carry post-release changes.
      # Report the baseline honestly rather than implying an exact release.
      say "gnadd $VERSION"
      say "channel=main"
      note "$VERSION is the release baseline; installed copies track main and may include post-release changes (see the repo's releases page)" ;;
    *)
      cat <<'USAGE'
gnadd: deterministic mechanics for the GNADD workflow

  state [--no-fetch]              snapshot: branch, tree, stashes, main classification
  start <N> <slug> [--carry]      resume or create issue-<N>/<slug> safely
  push                            checkpoint push: branch to origin, sets upstream, never forces
  guard-commit                    refuse commits on main/master/detached HEAD
  ship push [--any-branch]        push branch, detect existing PR
  ship status <pr>                mergeability + checks summary for the merge gate
  ship merge <pr> [--no-check]    squash-merge only if OPEN, MERGEABLE, and every check passed
  quickfix start <slug> [--carry] create quickfix/<slug> off verified-synced main
  quickfix guard                  refuse oversized or mechanics-touching diffs
  quickfix ship                   guard + push a quickfix branch, detect existing PR
  quickfix merge <pr> [--check <name>|--no-check]
                                  squash-merge only after the CI check passes
  round post --changed <text> (--feedback <text>|--feedback-file <f>|--no-feedback <why>)
                                  push the branch, then post this checkpoint's round comment
  round list [N]                  print the issue's round comments in order
  phase status                    the open milestone (title, counts, description) or none
  phase open <title> --description <text>
                                  open the next phase; refuses while one is open
  phase close <title> --verdict <text>
                                  close the phase; the verdict lands in its description
  sync-main                       return to main and fast-forward it (ff-only)
  cleanup <pr> <branch>           delete branch only after GitHub confirms the PR merged,
                                  that <branch> is its head, and nothing was committed after
  doctor [--rescue-main <name>]   diagnose bad states; lossless main rescue
  test                            detect and run the project's test command
  init [--strict] [--ci]          server-side rails: squash-only + main ruleset
  init land                       commit, push, and PR init's own files (AGENTS.md, CI workflow)
  conventions [--preview <cmd>]   write or update the GNADD block in AGENTS.md (idempotent)
  trace [show|reset]              per-invocation receipt log (.git/gnadd-trace.log)
  version                         release baseline + distribution channel

Exit codes: 0 ok · 1 usage/unexpected · 2 named state needing a human (state=NAME on stdout)
USAGE
      if [ -z "$cmd" ]; then exit 0; else exit 1; fi
      ;;
  esac
}

main "$@"
