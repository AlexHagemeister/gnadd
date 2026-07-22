#!/usr/bin/env bash
# gnadd — deterministic mechanics for the GNADD workflow.
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

VERSION="0.3.0"
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

gh_json() { # gh_json <field> <gh args...> — single field via --jq
  local field="$1"; shift
  "$GH" "$@" --json "$field" --jq ".$field"
}

# ---------------------------------------------------------------- trace
#
# Every subcommand leaves a receipt: one line per invocation (UTC time,
# command, exit status, branch) appended to gnadd-trace.log inside .git/ —
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
  # or command substitution — i.e. straight into the trace line (issue #38).
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

  if [ -n "$existing" ]; then
    # Resume. Tree is clean, so the checkout is safe.
    git checkout "$existing" >/dev/null 2>&1
    if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
      fetch_origin >/dev/null || true
      if ! git merge --ff-only '@{u}' >/dev/null 2>&1; then
        die_state BRANCH_DIVERGED_FROM_REMOTE "'$existing' and its remote have diverged; do not merge or rebase autonomously — a human decides"
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
      die_state FF_REFUSED "fast-forward of $MAIN from origin/$MAIN refused; stop and report — never merge, rebase, or reset here"
  fi
  git checkout -b "$target" >/dev/null 2>&1
  say "result=created"
  say "branch=$target"
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

  git push -u origin HEAD >/dev/null 2>&1 || die_state PUSH_FAILED "push to origin failed; check network/auth and retry"
  say "pushed=true"
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
  note "checks (informational; the human weighs them):"
  "$GH" pr checks "$pr" 2>&1 | sed 's/^/  /' || true
}

cmd_ship_merge() {
  local pr="${1:-}"
  [ -n "$pr" ] || usage_die "usage: gnadd ship merge <pr-number>"
  local state mergeable
  state="$(gh_json state pr view "$pr" 2>/dev/null)" || die_state PR_NOT_FOUND "no PR #$pr found"
  [ "$state" = "OPEN" ] || die_state PR_NOT_OPEN "PR #$pr is $state, not OPEN"
  mergeable="$(gh_json mergeable pr view "$pr" 2>/dev/null || echo UNKNOWN)"
  case "$mergeable" in
    MERGEABLE) ;;
    CONFLICTING) die_state PR_CONFLICTING "PR #$pr conflicts with $MAIN; hand resolution to the human — never resolve autonomously" ;;
    *) die_state MERGEABILITY_UNKNOWN "GitHub reports mergeable=$mergeable for PR #$pr; wait and re-run 'gnadd ship status $pr'" ;;
  esac
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
    die_state FF_REFUSED "fast-forward refused; stop and report — never retry without --ff-only"
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

  local br; br="$(current_branch)"
  [ "$br" != "$branch" ] || die_state ON_TARGET_BRANCH "cannot delete the branch you are standing on; run 'gnadd sync-main' first"

  if git show-ref --verify --quiet "refs/heads/$branch"; then
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
# the safety machinery itself (protected paths) — those changes take the
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
      die_state FF_REFUSED "fast-forward of $MAIN from origin/$MAIN refused; stop and report — never merge, rebase, or reset here"
  fi
  git checkout -b "$target" >/dev/null 2>&1
  say "result=created"
  say "branch=$target"
}

cmd_quickfix_guard() {
  # Scope: everything this quickfix would land — commits beyond origin/main
  # plus any uncommitted changes. Binary files count toward the file cap.
  local base="origin/$MAIN"
  git rev-parse --verify --quiet "$base" >/dev/null || base="$MAIN"

  local files
  files="$( { git diff --name-only "$base...HEAD" 2>/dev/null; git diff --name-only HEAD 2>/dev/null; } | sort -u | sed '/^$/d' )"
  local file_count
  file_count="$(printf '%s' "$files" | grep -c . || true)"

  local lines
  lines="$( { git diff --numstat "$base...HEAD" 2>/dev/null; git diff --numstat HEAD 2>/dev/null; } | \
    awk '{ if ($1 != "-") s += $1; if ($2 != "-") s += $2 } END { print s+0 }' )"

  say "files=$file_count"
  say "lines=$lines"

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
      die_state QF_NO_CHECKS "no CI checks reported for PR #$pr; nothing automated verified it — a human must decide (re-run with --no-check to accept that)"
    fi
    row="$(printf '%s\n' "$checks" | awk -F'\t' -v c="$check" '$1 == c { print; exit }')"
    [ -n "$row" ] || die_state QF_CHECK_NOT_FOUND "check '$check' not found on PR #$pr; available checks are informational — pick one with --check <name> or use --no-check deliberately"
    status="$(printf '%s\n' "$row" | awk -F'\t' '{ print $2 }')"
    case "$status" in
      pass) say "check=$check"; say "check_status=pass" ;;
      pending) die_state QF_CHECKS_PENDING "check '$check' is still running on PR #$pr; wait (gh pr checks $pr --watch) and re-run" ;;
      *) die_state QF_CHECK_FAILED "check '$check' reports '$status' on PR #$pr; a failing CI gate is a stop, not a wave-past" ;;
    esac
  fi

  cmd_ship_merge "$pr"
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
  #   2. step onto it (same commit as main — the working tree does not change)
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
  note "route them through the loop: open an issue, rename or PR this branch — never push them to $MAIN directly"
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
  if "$GH" repo edit \
      --enable-squash-merge \
      --enable-merge-commit=false \
      --enable-rebase-merge=false \
      --delete-branch-on-merge \
      --squash-merge-commit-title PR_TITLE \
      --squash-merge-commit-message PR_BODY >/dev/null 2>&1; then
    say "merge_policy=squash-only"
  else
    say "merge_policy=failed"
    note "gh repo edit failed (older gh version?); set squash-only + delete-branch-on-merge + squash message PR_TITLE/PR_BODY in repo Settings"
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
    if "$GH" api -X POST "repos/$repo/rulesets" --input - >/dev/null 2>&1 <<RULESET
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
      [ "$strict" = 1 ] && note "strict mode: no bypass — even admins must go through PRs"
    else
      say "ruleset=failed"
      note "could not create the ruleset via gh api; add one in repo Settings → Rules (require PR, block force pushes and deletion on $MAIN)"
    fi
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
      note "commit .github/workflows/gnadd-ci.yml through the loop (it is a normal change)"
    fi
  fi
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
    sync-main)    cmd_sync_main "$@" ;;
    cleanup)      cmd_cleanup "$@" ;;
    doctor)       cmd_doctor "$@" ;;
    test)         cmd_test "$@" ;;
    init)         cmd_init "$@" ;;
    trace)        cmd_trace "$@" ;;
    version|--version)
      # VERSION is stamped by scripts/release.sh at release time, but installs
      # track the default branch — so a copy may carry post-release changes.
      # Report the baseline honestly rather than implying an exact release.
      say "gnadd $VERSION"
      say "channel=main"
      note "$VERSION is the release baseline; installed copies track main and may include post-release changes (see the repo's releases page)" ;;
    *)
      cat <<'USAGE'
gnadd — deterministic mechanics for the GNADD workflow

  state [--no-fetch]              snapshot: branch, tree, stashes, main classification
  start <N> <slug> [--carry]      resume or create issue-<N>/<slug> safely
  guard-commit                    refuse commits on main/master/detached HEAD
  ship push [--any-branch]        push branch, detect existing PR
  ship status <pr>                mergeability + checks for the merge gate
  ship merge <pr>                 squash-merge (only if OPEN and MERGEABLE)
  quickfix start <slug> [--carry] create quickfix/<slug> off verified-synced main
  quickfix guard                  refuse oversized or mechanics-touching diffs
  quickfix ship                   guard + push a quickfix branch, detect existing PR
  quickfix merge <pr> [--check <name>|--no-check]
                                  squash-merge only after the CI check passes
  sync-main                       return to main and fast-forward it (ff-only)
  cleanup <pr> <branch>           delete branch only after GitHub confirms merge
  doctor [--rescue-main <name>]   diagnose bad states; lossless main rescue
  test                            detect and run the project's test command
  init [--strict] [--ci]          server-side rails: squash-only + main ruleset
  trace [show|reset]              per-invocation receipt log (.git/gnadd-trace.log)
  version                         release baseline + distribution channel

Exit codes: 0 ok · 1 usage/unexpected · 2 named state needing a human (state=NAME on stdout)
USAGE
      if [ -z "$cmd" ]; then exit 0; else exit 1; fi
      ;;
  esac
}

main "$@"
