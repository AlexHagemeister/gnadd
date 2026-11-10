#!/usr/bin/env bash
# Test suite for bin/gnadd. Zero dependencies beyond bash + git: gh is
# stubbed (test/stub/gh), remotes are local bare repos.
#
# Every incident that shaped a GNADD design decision (GNADD.md Part 5) has a
# regression test here. If you change bin/gnadd, this suite is what tells
# you whether the guarantees still hold.
#
# Usage: test/run.sh [name-or-pattern]
#   No argument runs every case. The last one, named lint, runs
#   scripts/lint.sh, the lint CI runs.
#   A name runs that case alone. A shell glob ('question_*') runs every
#   case it matches, and lint runs only if the filter selects it.
#   A filter that matches no case, or a run where no check ran, exits 2.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GNADD="$ROOT/bin/gnadd"
STUB="$ROOT/test/stub/gh"

if [ "$#" -gt 1 ]; then
  echo "usage: test/run.sh [name-or-pattern]" >&2
  exit 2
fi
FILTER="${1-}"

PASS=0
FAIL=0
CURRENT=""
FAILURES=()
CASES=0 # cases defined in this file
RAN=0   # cases that ran

# ---------------------------------------------------------------- helpers

fail() {
  FAIL=$((FAIL+1))
  FAILURES+=("$CURRENT: $*")
  printf 'FAIL %s: %s\n' "$CURRENT" "$*"
}

ok() { PASS=$((PASS+1)); }

expect_status() { # expect_status <want> <got>
  [ "$2" = "$1" ] && ok || fail "expected exit $1, got $2, output: $OUT"
}

expect_contains() { # expect_contains <needle>
  case "$OUT" in
    *"$1"*) ok ;;
    *) fail "output missing '$1', output: $OUT" ;;
  esac
}

expect_not_contains() {
  case "$OUT" in
    *"$1"*) fail "output unexpectedly contains '$1', output: $OUT" ;;
    *) ok ;;
  esac
}

# The stub log exists from setup_repo on, so a missing file is a miswired
# harness (wrong path, stub not logging), never "zero calls".
expect_gh_called() { # expect_gh_called <op> <message>
  if [ ! -f "$GH_STUB_LOG" ]; then
    fail "stub log missing at $GH_STUB_LOG; the harness is miswired"
  elif grep -q -- "$1" "$GH_STUB_LOG"; then
    ok
  else
    fail "$2"
  fi
}

expect_gh_not_called() { # expect_gh_not_called <op> <message>
  if [ ! -f "$GH_STUB_LOG" ]; then
    fail "stub log missing at $GH_STUB_LOG; the harness is miswired"
  elif grep -q -- "$1" "$GH_STUB_LOG"; then
    fail "$2"
  else
    ok
  fi
}

run() { # run <args...>: capture OUT and ST
  OUT="$("$GNADD" "$@" 2>&1)"
  ST=$?
}

git_q() { git "$@" >/dev/null 2>&1; }

# Fresh sandbox: bare origin + working clone with one commit on main.
setup_repo() {
  SANDBOX="$(mktemp -d)"
  cd "$SANDBOX"
  git_q init --bare origin.git
  git -C origin.git symbolic-ref HEAD refs/heads/main
  git_q clone origin.git work
  cd work
  git config user.email test@test && git config user.name test
  git config commit.gpgsign false
  echo "hello" > README.md
  git_q add README.md && git_q commit -m "init"
  git_q branch -M main
  git_q push -u origin main
  export GNADD_GH="$STUB" GH_STUB_LOG="$SANDBOX/gh.log"
  : > "$GH_STUB_LOG"
  unset GH_STUB_PR_STATE GH_STUB_PR_NUMBER GH_STUB_PR_URL \
        GH_STUB_MERGEABLE GH_STUB_MERGED_AT GH_STUB_MERGE_COMMIT \
        GH_STUB_CHECKS GH_STUB_FAIL GH_STUB_ROUND_COUNT \
        GH_STUB_ROUND_BODIES GH_STUB_COMMENT_FILE GH_STUB_PHASES \
        GH_STUB_PHASE_DESC GH_STUB_API_INPUT GH_STUB_RULESETS \
        GH_STUB_PR_HEAD GH_STUB_PR_HEAD_OID GH_STUB_RULESET_FAIL 2>/dev/null || true
  unset GH_STUB_QROWS GH_STUB_QROWS_5 GH_STUB_QROWS_6 GH_STUB_QROWS_7 GH_STUB_QBODY \
        GH_STUB_OPEN_ITEMS GH_STUB_ASSIGN_IGNORED GH_STUB_ISSUE_NUMBER GH_STUB_OTHER_ASSIGNEES \
        GH_STUB_ITEM_META GH_STUB_UNASSIGN_FAIL GH_STUB_ITEM_READ_FAIL GH_STUB_QREAD_FAIL \
        GH_STUB_ISSUE_CLOSE_FAIL 2>/dev/null || true
}

# Push a commit to origin/main from a second clone (simulates a merge or a
# collaborator) without touching the working clone.
advance_origin_main() {
  ( cd "$SANDBOX"
    git_q clone origin.git other
    cd other
    git config user.email o@o && git config user.name o
    echo "$RANDOM" >> upstream.txt
    git_q add upstream.txt && git_q commit -m "upstream change"
    git_q push origin main )
}

# Each case is one `if t <name>; then ... fi` block. t says whether the case
# is selected, so a skipped case's body never runs and leaves no state.
t() {
  CASES=$((CASES+1))
  if [ -n "$FILTER" ]; then
    case "$1" in $FILTER) ;; *) return 1 ;; esac
  fi
  RAN=$((RAN+1))
  CURRENT="$1"
}

# Helpers for later sections. They live up here, outside every case, so a
# filtered run defines them whichever cases it selects.
add_wt() { # add_wt <name>: linked worktree at $SANDBOX/<name>, detached at main; sets WT
  git_q -C "$SANDBOX/work" worktree add --detach "$SANDBOX/$1"
  WT="$(cd "$SANDBOX/$1" && pwd -P)"
  git -C "$WT" config user.email test@test
}
folder_snapshot() { # folder_snapshot <dir>: HEAD, branch, and status of one folder
  printf '%s %s %s' "$(git -C "$1" rev-parse HEAD)" "$(git -C "$1" symbolic-ref --quiet --short HEAD || echo detached)" "$(git -C "$1" status --porcelain | tr '\n' ' ')"
}
commit_setup_line() { # commit_setup_line <command>: put the line on main and origin/main
  printf 'Worktree setup: %s\n' "$1" > "$SANDBOX/work/AGENTS.md"
  git_q -C "$SANDBOX/work" add AGENTS.md
  git_q -C "$SANDBOX/work" commit -m "setup line"
  git_q -C "$SANDBOX/work" push origin main
}
setup_runs() { if [ -f "$SANDBOX/setup.log" ]; then wc -l < "$SANDBOX/setup.log" | tr -d ' '; else echo 0; fi; }
branch_on_origin() { # branch_on_origin <branch>: local branch with one commit, pushed and tracking; work returns to main
  git_q -C "$SANDBOX/work" checkout -b "$1"
  echo one > "$SANDBOX/work/one.txt"
  git_q -C "$SANDBOX/work" add one.txt && git_q -C "$SANDBOX/work" commit -m "one"
  git_q -C "$SANDBOX/work" push -u origin "$1"
  git_q -C "$SANDBOX/work" checkout main
}
advance_origin_branch() { # advance_origin_branch <branch>: a commit lands on origin's copy from another clone
  ( cd "$SANDBOX"
    rm -rf adv && git_q clone origin.git adv
    cd adv
    git config user.email o@o && git config user.name o
    git_q checkout "$1"
    echo "$RANDOM" >> remote.txt
    git_q add remote.txt && git_q commit -m "remote change"
    git_q push origin "$1" )
}
local_commit() { # local_commit <dir>: a commit origin does not have
  echo local >> "$1/local.txt"
  git_q -C "$1" add local.txt && git_q -C "$1" commit -m "local change"
}
fact_line() { printf '%s\n' "$OUT" | grep -q "^$1\$"; }
q_reset() { # setup_repo clears the question fixtures. This adds the comment file.
  export GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
}

# ---------------------------------------------------------------- state

if t state_synced; then setup_repo
run state
expect_status 0 "$ST"
expect_contains "main_state=synced"
expect_contains "tree=clean"
expect_contains "branch=main"
fi

if t state_behind; then setup_repo
advance_origin_main
run state
expect_status 0 "$ST"
expect_contains "main_state=behind"
expect_contains "main_behind=1"
fi

if t state_diverged; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray commit on main"
run state
expect_status 0 "$ST"
expect_contains "main_state=diverged"
expect_contains "main_ahead=1"
expect_contains "stray commit on main"
expect_not_contains "commits on origin/main that local lacks"
fi

if t state_diverged_lists_both_sides; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray commit on main"
advance_origin_main
run state
expect_contains "main_state=diverged"
expect_contains "commits on origin/main that local lacks"
fi

if t state_names_dirty_files; then setup_repo
echo y > untracked.txt
echo changed >> README.md
run state
expect_contains "tree=dirty"
expect_contains "dirty_files=2"
expect_contains " M README.md"
expect_contains "?? untracked.txt"
fi

if t state_reports_stash; then setup_repo
echo x > s.txt && git_q add s.txt && git stash >/dev/null 2>&1
run state
expect_contains "stashes=1"
fi

if t state_reports_upstream; then setup_repo
run start 3 upstream-lines
run state
expect_contains "upstream=none"
expect_contains "ahead_of_upstream=0"
echo a > a.txt && git_q add a.txt && git_q commit -m "local only"
run state
expect_contains "upstream=none"
expect_contains "ahead_of_upstream=1"
run push
expect_status 0 "$ST"
run state
expect_contains "upstream=origin/issue-3/upstream-lines"
expect_contains "ahead_of_upstream=0"
echo b > b.txt && git_q add b.txt && git_q commit -m "one more"
run state
expect_contains "ahead_of_upstream=1"
fi

# ---------------------------------------------------------------- start

if t start_fresh; then setup_repo
run start 5 fix-thing
expect_status 0 "$ST"
expect_contains "result=created"
expect_contains "branch=issue-5/fix-thing"
[ "$(git symbolic-ref --short HEAD)" = "issue-5/fix-thing" ] && ok || fail "not on new branch"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main moved"
fi

if t start_syncs_behind_main; then setup_repo
advance_origin_main
run start 6 sync-me
expect_status 0 "$ST"
expect_contains "result=created"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main not fast-forwarded"
fi

if t start_halts_on_diverged_main; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
run start 7 nope
expect_status 2 "$ST"
expect_contains "state=DIVERGED_MAIN"
git show-ref --verify --quiet refs/heads/issue-7/nope && fail "branch was created despite halt" || ok
fi

if t start_halts_on_dirty_tree; then setup_repo
echo x > dirty.txt
run start 8 nope
expect_status 2 "$ST"
expect_contains "state=DIRTY_TREE"
git show-ref --verify --quiet refs/heads/issue-8/nope && fail "branch was created despite halt" || ok
fi

if t start_carry; then setup_repo
echo x > dirty.txt
run start 9 rescue --carry
expect_status 0 "$ST"
expect_contains "result=created-carry"
[ "$(git symbolic-ref --short HEAD)" = "issue-9/rescue" ] && ok || fail "not on carry branch"
[ -f dirty.txt ] && ok || fail "dirty file lost in carry"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main gained a commit"
fi

if t start_carry_refuses_off_main; then setup_repo
git_q checkout -b issue-1/elsewhere
echo x > dirty.txt
run start 9 rescue --carry
expect_status 2 "$ST"
expect_contains "state=NOT_ON_MAIN"
fi

if t start_resume_pulls_remote; then setup_repo
run start 10 resume-me
git_q push -u origin HEAD
# Advance the issue branch on the remote from a second clone.
( cd "$SANDBOX" && git_q clone origin.git other2 && cd other2
  git config user.email o@o && git config user.name o
  git_q checkout issue-10/resume-me
  echo remote >> r.txt && git_q add r.txt && git_q commit -m "remote work"
  git_q push origin issue-10/resume-me )
git_q checkout main
run start 10 resume-me
expect_status 0 "$ST"
expect_contains "result=resumed"
[ -f r.txt ] && ok || fail "remote work not pulled on resume"
fi

if t start_resume_halts_on_diverged_branch; then setup_repo
run start 11 diverge-me
git_q push -u origin HEAD
( cd "$SANDBOX" && git_q clone origin.git other3 && cd other3
  git config user.email o@o && git config user.name o
  git_q checkout issue-11/diverge-me
  echo remote >> r.txt && git_q add r.txt && git_q commit -m "remote work"
  git_q push origin issue-11/diverge-me )
echo local >> l.txt && git_q add l.txt && git_q commit -m "local work"
git_q checkout main
run start 11 diverge-me
expect_status 2 "$ST"
expect_contains "state=BRANCH_DIVERGED_FROM_REMOTE"
fi

if t start_resumes_remote_only_branch; then setup_repo
# Fresh clone, same issue: the branch exists on origin but not locally.
( cd "$SANDBOX" && git_q clone origin.git other4 && cd other4
  git config user.email o@o && git config user.name o
  git_q checkout -b issue-13/elsewhere
  echo remote >> r.txt && git_q add r.txt && git_q commit -m "remote work"
  git_q push -u origin issue-13/elsewhere )
run start 13 any-slug
expect_status 0 "$ST"
expect_contains "result=resumed"
expect_contains "branch=issue-13/elsewhere"
expect_contains "upstream=origin/issue-13/elsewhere"
[ -f r.txt ] && ok || fail "remote branch content not checked out"
[ "$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)" = "origin/issue-13/elsewhere" ] && ok || fail "upstream not set on remote-only resume"
fi

# ---------------------------------------------------------------- guard-commit

if t guard_commit_on_main; then setup_repo
run guard-commit
expect_status 2 "$ST"
expect_contains "state=ON_MAIN"
fi

if t guard_commit_on_issue_branch; then setup_repo
git_q checkout -b issue-3/ok
run guard-commit
expect_status 0 "$ST"
expect_contains "issue=3"
fi

if t guard_commit_detached; then setup_repo
git_q checkout --detach HEAD
run guard-commit
expect_status 2 "$ST"
expect_contains "state=DETACHED_HEAD"
fi

# ---------------------------------------------------------------- ship

if t ship_push_happy; then setup_repo
run start 12 shippable
echo work > w.txt && git_q add w.txt && git_q commit -m "work"
run ship push
expect_status 0 "$ST"
expect_contains "pushed=true"
expect_contains "pr_exists=false"
git ls-remote --exit-code --heads origin issue-12/shippable >/dev/null 2>&1 && ok || fail "branch not on remote"
fi

if t ship_push_nothing_to_ship; then setup_repo
run start 13 empty
run ship push
expect_status 2 "$ST"
expect_contains "state=NOTHING_TO_SHIP"
fi

if t ship_push_refuses_main; then setup_repo
run ship push
expect_status 2 "$ST"
expect_contains "state=ON_MAIN"
fi

if t ship_push_refuses_random_branch; then setup_repo
git_q checkout -b experiment
echo x > x.txt && git_q add x.txt && git_q commit -m x
run ship push
expect_status 2 "$ST"
expect_contains "state=NOT_ISSUE_BRANCH"
run ship push --any-branch
expect_status 0 "$ST"
fi

if t ship_push_detects_existing_pr; then setup_repo
run start 14 has-pr
echo work > w.txt && git_q add w.txt && git_q commit -m "work"
export GH_STUB_PR_STATE=OPEN GH_STUB_PR_NUMBER=44 GH_STUB_PR_URL=https://x/pull/44
run ship push
expect_status 0 "$ST"
expect_contains "pr_exists=true"
expect_contains "pr_number=44"
fi

if t ship_merge_conflicting_never_merges; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=CONFLICTING
run ship merge 44
expect_status 2 "$ST"
expect_contains "state=PR_CONFLICTING"
expect_gh_not_called "pr merge" "gh pr merge was called on a conflicting PR"
fi

if t ship_merge_ok; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='test\tpass\t5s\turl'
run ship merge 44
expect_status 0 "$ST"
expect_contains "checks=pass"
expect_contains "merged=true"
expect_gh_called "pr merge 44 --squash" "gh pr merge --squash not called"
fi

if t ship_merge_waits_for_pending_checks; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='CodeRabbit\tpass\t0\turl\ntest\tpending\t0\turl'
run ship merge 44
expect_status 2 "$ST"
expect_contains "state=CHECKS_PENDING"
expect_contains "gh pr checks 44 --watch"
expect_gh_not_called "pr merge" "merged with CI still pending"
fi

if t ship_merge_refuses_any_failed_check; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='test\tpass\t5s\turl\ntest-macos\tfail\t9s\turl'
run ship merge 44
expect_status 2 "$ST"
expect_contains "state=CHECK_FAILED"
expect_contains "test-macos=fail"
expect_gh_not_called "pr merge" "merged despite failing check"
fi

if t ship_merge_skipping_check_is_not_a_failure; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='CodeRabbit\tskipping\t0\turl\ntest\tpass\t5s\turl'
run ship merge 44
expect_status 0 "$ST"
expect_contains "merged=true"
fi

if t ship_merge_no_checks_no_workflow; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
run ship merge 44
expect_status 2 "$ST"
expect_contains "state=NO_CHECKS"
expect_gh_not_called "pr merge" "merged with nothing verified"
run ship merge 44 --no-check
expect_status 0 "$ST"
expect_contains "merged=true"
fi

if t ship_merge_no_checks_but_workflow_means_pending; then setup_repo
mkdir -p .github/workflows && echo "on: pull_request" > .github/workflows/ci.yml
git_q add .github && git_q commit -m "ci"
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
run ship merge 44
expect_status 2 "$ST"
expect_contains "state=CHECKS_PENDING"
expect_contains "no checks reported yet"
expect_gh_not_called "pr merge" "merged before the workflow started"
fi

if t ship_status_reports_checks_summary; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
run ship status 44
expect_contains "checks=none"
export GH_STUB_CHECKS='test\tpending\t0\turl'
run ship status 44
expect_contains "checks=pending"
export GH_STUB_CHECKS='test\tpass\t5s\turl'
run ship status 44
expect_contains "checks=pass"
fi

if t quickfix_merge_gate_is_the_named_check_only; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='other\tpending\t0\turl\ntest\tpass\t5s\turl'
run quickfix merge 50
expect_status 0 "$ST"
expect_contains "merged=true"
fi

if t ship_merge_unknown_mergeability; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=UNKNOWN
run ship merge 44
expect_status 2 "$ST"
expect_contains "state=MERGEABILITY_UNKNOWN"
fi

# ---------------------------------------------------------------- sync-main / cleanup

if t sync_main_fast_forwards; then setup_repo
git_q checkout -b issue-15/done
advance_origin_main
run sync-main
expect_status 0 "$ST"
expect_contains "synced=true"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main not synced"
fi

if t sync_main_halts_on_divergence; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
git_q checkout -b issue-16/done
run sync-main
expect_status 2 "$ST"
expect_contains "state=DIVERGED_MAIN"
fi

if t cleanup_refuses_unmerged; then setup_repo
git_q branch issue-17/keep
export GH_STUB_PR_STATE=OPEN
run cleanup 45 issue-17/keep
expect_status 2 "$ST"
expect_contains "state=NOT_MERGED"
git show-ref --verify --quiet refs/heads/issue-17/keep && ok || fail "branch deleted despite unmerged PR"
fi

if t cleanup_after_merge; then setup_repo
git_q checkout -b issue-18/gone
echo x > x.txt && git_q add x.txt && git_q commit -m x
git_q push -u origin HEAD
git_q checkout main
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-07-17T00:00:00Z GH_STUB_MERGE_COMMIT=deadbeef
export GH_STUB_PR_HEAD=issue-18/gone GH_STUB_PR_HEAD_OID="$(git rev-parse issue-18/gone)"
run cleanup 46 issue-18/gone
expect_status 0 "$ST"
expect_contains "local_deleted=true"
expect_contains "remote_deleted=true"
expect_contains "merge_commit=deadbeef"
git show-ref --verify --quiet refs/heads/issue-18/gone && fail "local branch survived" || ok
git ls-remote --exit-code --heads origin issue-18/gone >/dev/null 2>&1 && fail "remote branch survived" || ok
fi

if t cleanup_refuses_from_target_branch; then setup_repo
git_q checkout -b issue-19/here
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-07-17T00:00:00Z GH_STUB_PR_HEAD=issue-19/here
run cleanup 47 issue-19/here
expect_status 2 "$ST"
expect_contains "state=ON_TARGET_BRANCH"
fi

if t cleanup_refuses_branch_mismatch; then setup_repo
git_q checkout -b rescue/stray
echo x > x.txt && git_q add x.txt && git_q commit -m "stray"
git_q checkout main
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-07-17T00:00:00Z GH_STUB_PR_HEAD=quickfix/other
run cleanup 48 rescue/stray
expect_status 2 "$ST"
expect_contains "state=BRANCH_MISMATCH"
expect_contains "quickfix/other"
git show-ref --verify --quiet refs/heads/rescue/stray && ok || fail "branch deleted despite PR head mismatch"
fi

if t cleanup_refuses_unknown_head; then setup_repo
git_q branch issue-20/keep
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-07-17T00:00:00Z
run cleanup 49 issue-20/keep
expect_status 2 "$ST"
expect_contains "state=BRANCH_MISMATCH"
git show-ref --verify --quiet refs/heads/issue-20/keep && ok || fail "branch deleted with unknown PR head"
fi

if t cleanup_refuses_commits_after_merged_head; then setup_repo
git_q checkout -b issue-21/late
echo x > x.txt && git_q add x.txt && git_q commit -m "in the PR"
merged_head="$(git rev-parse HEAD)"
echo y > y.txt && git_q add y.txt && git_q commit -m "after the merge"
git_q checkout main
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-07-17T00:00:00Z
export GH_STUB_PR_HEAD=issue-21/late GH_STUB_PR_HEAD_OID="$merged_head"
run cleanup 50 issue-21/late
expect_status 2 "$ST"
expect_contains "state=UNMERGED_COMMITS"
expect_contains "1 commit(s) after"
git show-ref --verify --quiet refs/heads/issue-21/late && ok || fail "branch with post-merge commits deleted"
fi

# ---------------------------------------------------------------- doctor

if t doctor_clean; then setup_repo
run doctor
expect_status 0 "$ST"
expect_contains "findings=0"
fi

if t doctor_finds_bad_states; then setup_repo
echo x > s.txt && git_q add s.txt && git stash >/dev/null 2>&1
echo y > local.txt && git_q add local.txt && git_q commit -m "stray"
run doctor
expect_status 0 "$ST"
expect_contains "finding=DIVERGED_MAIN"
expect_contains "finding=STASHES"
fi

if t doctor_rescue_main; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray commit"
STRAY="$(git rev-parse HEAD)"
run doctor --rescue-main rescue/stray
expect_status 0 "$ST"
expect_contains "rescued=true"
[ "$(git rev-parse rescue/stray)" = "$STRAY" ] && ok || fail "rescue branch lost the stray commit"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main not realigned"
[ "$(git symbolic-ref --short HEAD)" = "rescue/stray" ] && ok || fail "not standing on rescue branch"
fi

if t doctor_rescue_onto_quickfix_name_ships_through_quickfix; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray commit"
run doctor --rescue-main quickfix/stray
expect_status 0 "$ST"
expect_contains "rescued=true"
expect_contains "/quickfix-gnadd"
expect_contains "gnadd start <N> <slug> --from quickfix/stray"
expect_contains "gnadd drop quickfix/stray"
run quickfix ship
expect_status 0 "$ST"
expect_contains "guard=ok"
expect_contains "pushed=true"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main gained a commit"
fi

if t start_from_renames_rescued_branch_into_issue_branch; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray commit"
STRAY="$(git rev-parse HEAD)"
run doctor --rescue-main rescue/stray
run start 21 rescued-work --from rescue/stray
expect_status 0 "$ST"
expect_contains "result=created-from"
expect_contains "branch=issue-21/rescued-work"
expect_contains "from=rescue/stray"
[ "$(git symbolic-ref --short HEAD)" = "issue-21/rescued-work" ] && ok || fail "not on the issue branch"
[ "$(git rev-parse HEAD)" = "$STRAY" ] && ok || fail "issue branch lost the stray commit"
git show-ref --verify --quiet refs/heads/rescue/stray && fail "rescue branch still exists after rename" || ok
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main moved"
fi

if t start_from_refusals; then setup_repo
run start 22 nope --from nosuch
expect_status 2 "$ST"
expect_contains "state=FROM_NOT_FOUND"
run start 22 nope --from main
expect_status 2 "$ST"
expect_contains "state=FROM_IS_MAIN"
git_q checkout -b issue-22/already && git_q checkout -b rescue/x && git_q checkout main
run start 22 nope --from rescue/x
expect_status 2 "$ST"
expect_contains "state=FROM_HAS_EXISTING_BRANCH"
run start 22 nope --from rescue/x --carry
expect_status 1 "$ST"
fi

if t drop_lists_commits_and_refuses_without_yes; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray commit"
run doctor --rescue-main rescue/stray
run sync-main
run drop rescue/stray
expect_status 2 "$ST"
expect_contains "state=DROP_NEEDS_CONFIRM"
expect_contains "commits_beyond_origin_main=1"
expect_contains "stray commit"
git show-ref --verify --quiet refs/heads/rescue/stray && ok || fail "branch deleted without --yes"
run drop rescue/stray --yes
expect_status 0 "$ST"
expect_contains "dropped=true"
git show-ref --verify --quiet refs/heads/rescue/stray && fail "branch survived --yes" || ok
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main moved"
fi

if t drop_refusals; then setup_repo
run drop main --yes
expect_status 2 "$ST"
expect_contains "state=DROP_MAIN"
run drop nosuch --yes
expect_status 2 "$ST"
expect_contains "state=DROP_NOT_FOUND"
git_q checkout -b rescue/here
run drop rescue/here --yes
expect_status 2 "$ST"
expect_contains "state=ON_TARGET_BRANCH"
git show-ref --verify --quiet refs/heads/rescue/here && ok || fail "deleted the checked-out branch"
fi

if t doctor_rescue_refuses_when_not_diverged; then setup_repo
run doctor --rescue-main rescue/nothing
expect_status 2 "$ST"
expect_contains "state=NOT_DIVERGED"
fi

# ---------------------------------------------------------------- worktrees
#
# Issue #115: the loop works from inside a linked worktree. Each linked
# folder is added detached, the way an agent's own worktree usually starts.



if t wt_start_inside_linked_worktree_builds_from_origin_main; then setup_repo
add_wt wt1
advance_origin_main
MAIN_BEFORE="$(git -C "$SANDBOX/work" rev-parse main)"
WORK_BEFORE="$(folder_snapshot "$SANDBOX/work")"
cd "$WT"
run start 30 alpha
expect_status 0 "$ST"
expect_contains "result=created"
expect_contains "branch=issue-30/alpha"
[ "$(git symbolic-ref --short HEAD)" = "issue-30/alpha" ] && ok || fail "not on the issue branch in the worktree"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && ok || fail "issue branch not built from current origin/main"
git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 && fail "fresh branch tracks something before its first push" || ok
[ "$(git rev-parse main)" = "$MAIN_BEFORE" ] && ok || fail "local main moved from inside the worktree"
[ "$(folder_snapshot "$SANDBOX/work")" = "$WORK_BEFORE" ] && ok || fail "the main checkout changed"
fi

if t wt_start_inside_linked_worktree_still_halts_on_diverged_main; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
add_wt wt1
cd "$WT"
run start 30 alpha
expect_status 2 "$ST"
expect_contains "state=DIVERGED_MAIN"
git show-ref --verify --quiet refs/heads/issue-30/alpha && fail "branch created on a diverged main" || ok
fi

# Issue #116: a `Worktree setup:` line runs once per fresh linked worktree.
# The command logs the folder it ran in to a file outside every tree.

if t wt_setup_line_runs_in_fresh_worktree; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log && echo installing"
add_wt wt1
cd "$WT"
run start 40 setup
expect_status 0 "$ST"
expect_contains "branch=issue-40/setup"
expect_contains "setup=ran"
expect_contains "  | installing"
[ "$(setup_runs)" = "1" ] && ok || fail "setup ran $(setup_runs) times, wanted 1"
[ "$(cat "$SANDBOX/setup.log" 2>/dev/null)" = "$WT" ] && ok || fail "setup did not run in the worktree folder"
[ -z "$(git status --porcelain)" ] && ok || fail "setup marker landed in the tree"
fi

if t wt_setup_failure_halts_and_rerun_retries; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log && echo boom && exit 3"
add_wt wt1
cd "$WT"
run start 41 broken
expect_status 2 "$ST"
expect_contains "state=SETUP_FAILED"
expect_contains "not ready"
expect_contains "  | boom"
expect_not_contains "setup=ran"
run start 41 broken
expect_status 2 "$ST"
[ "$(setup_runs)" = "2" ] && ok || fail "rerun after a failed setup did not retry it"
fi

if t wt_setup_not_rerun_for_next_issue_in_same_folder; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log"
add_wt wt1
cd "$WT"
run start 42 first
run sync-main
run start 43 second
expect_status 0 "$ST"
expect_contains "branch=issue-43/second"
expect_not_contains "setup"
[ "$(setup_runs)" = "1" ] && ok || fail "an already set-up folder was set up again"
fi

if t wt_setup_absent_line_runs_nothing; then setup_repo
add_wt wt1
cd "$WT"
run start 44 plain
expect_status 0 "$ST"
expect_not_contains "setup"
fi

if t wt_setup_skips_primary_checkout; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log"
run start 45 primary
expect_status 0 "$ST"
expect_not_contains "setup"
[ "$(setup_runs)" = "0" ] && ok || fail "setup ran in the primary checkout"
fi

# The SETUP_FAILED recipe must work as printed: fix the cause, rerun the
# plain start. $SANDBOX/ok stands in for the fix.
if t wt_setup_retry_reaches_setup_on_a_tree_the_setup_dirtied; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log; cp README.md .env; test -f $SANDBOX/ok"
add_wt wt1
cd "$WT"
run start 46 dirty
expect_status 2 "$ST"
expect_contains "state=SETUP_FAILED"
touch "$SANDBOX/ok"
run start 46 dirty
expect_status 0 "$ST"
expect_contains "setup=ran"
expect_not_contains "DIRTY_TREE"
[ "$(setup_runs)" = "2" ] && ok || fail "the rerun did not retry the setup"
[ -f .env ] && ok || fail "the file the setup wrote was lost"
fi

if t wt_setup_retry_after_carry_keeps_carried_change; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log; test -f $SANDBOX/ok"
git_q -C "$SANDBOX/work" checkout -b elsewhere
git_q -C "$SANDBOX/work" worktree add "$SANDBOX/wtm" main
cd "$SANDBOX/wtm"
echo carried > carried.txt
run start 47 carry --carry
expect_status 2 "$ST"
expect_contains "state=SETUP_FAILED"
touch "$SANDBOX/ok"
run start 47 carry
expect_status 0 "$ST"
expect_contains "setup=ran"
[ "$(cat carried.txt 2>/dev/null)" = "carried" ] && ok || fail "the carried change was disturbed"
[ "$(git symbolic-ref --short HEAD)" = "issue-47/carry" ] && ok || fail "left the issue branch"
fi

if t wt_setup_failure_after_from_names_plain_start_that_retries; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log; test -f $SANDBOX/ok"
add_wt wt1
cd "$WT"
git_q checkout -b rescue/x
run start 48 rescued --from rescue/x
expect_status 2 "$ST"
expect_contains "start 48 rescued"
touch "$SANDBOX/ok"
run start 48 rescued
expect_status 0 "$ST"
expect_contains "setup=ran"
fi

if t wt_setup_none_runs_nothing; then setup_repo
commit_setup_line "none"
add_wt wt1
cd "$WT"
run start 49 none
expect_status 0 "$ST"
expect_not_contains "setup"
fi

if t wt_setup_returns_when_the_command_exits; then setup_repo
commit_setup_line "sleep 8 & echo state=FAKE"
add_wt wt1
cd "$WT"
T0=$SECONDS
run start 50 bg
expect_status 0 "$ST"
[ $((SECONDS - T0)) -lt 5 ] && ok || fail "start waited on a process the setup left running"
expect_contains "  | state=FAKE"
printf '%s\n' "$OUT" | grep -q '^state=FAKE' && fail "setup output readable as a key=value line" || ok
fi

if t wt_setup_strips_wrapping_backticks; then setup_repo
commit_setup_line '`echo Done`'
add_wt wt1
cd "$WT"
run start 51 ticks
expect_status 0 "$ST"
expect_contains "  | Done"
expect_contains "setup=ran"
fi

if t wt_setup_reads_agents_md_only; then setup_repo
printf 'Worktree setup: echo claude >> %s/setup.log\n' "$SANDBOX" > CLAUDE.md
git_q add CLAUDE.md && git_q commit -m "claude line"
commit_setup_line "echo agents >> $SANDBOX/setup.log"
add_wt wt1
cd "$WT"
run start 52 agents
expect_status 0 "$ST"
[ "$(cat "$SANDBOX/setup.log" 2>/dev/null)" = "agents" ] && ok || fail "setup line not read from AGENTS.md alone"
fi

# A retry must never skip a check the ordinary resume makes. The retry
# shortcut is only for a dirty tree after a setup that did not finish here.
# With a clean tree, or in a folder where no setup ever started, start takes
# the ordinary path and then runs the setup as a first run would.

if t wt_setup_first_resume_in_worktree_added_on_branch_fast_forwards; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log"
branch_on_origin issue-60/z
advance_origin_branch issue-60/z
git_q -C "$SANDBOX/work" worktree add "$SANDBOX/wtz" issue-60/z
cd "$SANDBOX/wtz"
run start 60 z
expect_status 0 "$ST"
expect_contains "result=resumed"
expect_contains "setup=ran"
git_q fetch origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/issue-60/z)" ] && ok || fail "the resume skipped the fast-forward pull"
fi

if t wt_setup_first_resume_in_worktree_added_on_branch_halts_on_diverged; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log"
branch_on_origin issue-61/z
advance_origin_branch issue-61/z
git_q -C "$SANDBOX/work" worktree add "$SANDBOX/wtz" issue-61/z
local_commit "$SANDBOX/wtz"
cd "$SANDBOX/wtz"
run start 61 z
expect_status 2 "$ST"
expect_contains "state=BRANCH_DIVERGED_FROM_REMOTE"
expect_not_contains "result=resumed"
[ "$(setup_runs)" = "0" ] && ok || fail "setup ran on a branch diverged from its remote"
fi

if t wt_setup_dirty_tree_with_no_failed_setup_still_halts; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log"
git_q -C "$SANDBOX/work" branch issue-62/z
git_q -C "$SANDBOX/work" worktree add "$SANDBOX/wtz" issue-62/z
cd "$SANDBOX/wtz"
echo wip > wip.txt
run start 62 z
expect_status 2 "$ST"
expect_contains "state=DIRTY_TREE"
[ "$(setup_runs)" = "0" ] && ok || fail "setup ran past a dirty tree in a folder where no setup had failed"
fi

if t wt_setup_retry_on_clean_tree_is_an_ordinary_resume; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log; test -f $SANDBOX/ok"
branch_on_origin issue-63/z
add_wt wt1
cd "$WT"
run start 63 z
expect_status 2 "$ST"
expect_contains "state=SETUP_FAILED"
advance_origin_branch issue-63/z
touch "$SANDBOX/ok"
run start 63 z
expect_status 0 "$ST"
expect_contains "setup=ran"
expect_not_contains "ignored"
git_q fetch origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/issue-63/z)" ] && ok || fail "the clean rerun skipped the fast-forward pull"
[ "$(setup_runs)" = "2" ] && ok || fail "the clean rerun did not retry the setup"
fi

if t wt_setup_retry_on_clean_tree_halts_on_diverged; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log; test -f $SANDBOX/ok"
branch_on_origin issue-64/z
add_wt wt1
cd "$WT"
run start 64 z
expect_contains "state=SETUP_FAILED"
advance_origin_branch issue-64/z
local_commit "$WT"
touch "$SANDBOX/ok"
run start 64 z
expect_status 2 "$ST"
expect_contains "state=BRANCH_DIVERGED_FROM_REMOTE"
expect_not_contains "result=resumed"
[ "$(setup_runs)" = "1" ] && ok || fail "the setup was retried on a branch diverged from its remote"
fi

if t wt_setup_retry_on_dirty_tree_halts_on_diverged; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log; cp README.md .env; test -f $SANDBOX/ok"
branch_on_origin issue-65/z
add_wt wt1
cd "$WT"
run start 65 z
expect_contains "state=SETUP_FAILED"
advance_origin_branch issue-65/z
local_commit "$WT"
touch "$SANDBOX/ok"
run start 65 z
expect_status 2 "$ST"
expect_contains "state=BRANCH_DIVERGED_FROM_REMOTE"
expect_not_contains "result=resumed"
[ "$(setup_runs)" = "1" ] && ok || fail "the setup was retried on a branch diverged from its remote"
[ -f .env ] && ok || fail "the file the setup wrote was lost"
fi

if t wt_setup_retry_on_dirty_tree_says_the_branch_is_behind; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log; cp README.md .env; test -f $SANDBOX/ok"
branch_on_origin issue-66/z
add_wt wt1
cd "$WT"
run start 66 z
expect_contains "state=SETUP_FAILED"
HEAD_BEFORE="$(git rev-parse HEAD)"
advance_origin_branch issue-66/z
touch "$SANDBOX/ok"
run start 66 z
expect_status 0 "$ST"
expect_contains "setup=ran"
expect_contains "1 commit(s) behind its remote and was not fast-forwarded"
[ "$(git rev-parse HEAD)" = "$HEAD_BEFORE" ] && ok || fail "HEAD moved under uncommitted changes"
[ -f .env ] && ok || fail "the file the setup wrote was lost"
fi

if t wt_setup_retry_says_an_ignored_flag_was_ignored; then setup_repo
commit_setup_line "pwd -P >> $SANDBOX/setup.log; cp README.md .env; test -f $SANDBOX/ok"
add_wt wt1
cd "$WT"
run start 67 flags
expect_contains "state=SETUP_FAILED"
expect_not_contains "ignored"
run start 67 flags --carry
expect_status 2 "$ST"
expect_contains "note: --carry ignored"
touch "$SANDBOX/ok"
run start 67 flags --from rescue/gone
expect_status 0 "$ST"
expect_contains "note: --from rescue/gone ignored"
expect_contains "setup=ran"
fi

# Whatever the setup prints, each fact the script prints is a line of its own.

if t wt_setup_output_never_glues_onto_a_fact_line; then setup_repo
commit_setup_line "printf boom; exit 3"
add_wt wt1
cd "$WT"
run start 68 glue
expect_status 2 "$ST"
fact_line "state=SETUP_FAILED" && ok || fail "state= does not start a line, output: $OUT"
fact_line "  | boom" && ok || fail "the output line was not ended, output: $OUT"
cd "$SANDBOX/work"
commit_setup_line "printf foo"
add_wt wt2
cd "$WT"
run start 69 glue
expect_status 0 "$ST"
fact_line "setup=ran" && ok || fail "setup=ran does not start a line, output: $OUT"
cd "$SANDBOX/work"
commit_setup_line "true"
add_wt wt3
cd "$WT"
run start 70 quiet
expect_status 0 "$ST"
fact_line "setup=ran" && ok || fail "setup=ran does not start a line after empty output, output: $OUT"
expect_not_contains "  | "
cd "$SANDBOX/work"
commit_setup_line "printf 'one\\rstate=FAKE\\r\\ntwo\\rsetup=fake'"
add_wt wt4
cd "$WT"
run start 71 cr
expect_status 0 "$ST"
case "$OUT" in *"$(printf '\r')"*) fail "a carriage return reached the output" ;; *) ok ;; esac
fact_line "  | state=FAKE" && ok || fail "text after a carriage return is not on a prefixed line, output: $OUT"
fact_line "  | setup=fake" && ok || fail "text after a carriage return is not on a prefixed line, output: $OUT"
fact_line "setup=ran" && ok || fail "setup=ran does not start a line, output: $OUT"
[ "$(printf '%s\n' "$OUT" | grep -c '^setup=')" = "1" ] && ok || fail "setup output read as a fact, output: $OUT"
fi

# Backticks are stripped only when the value is exactly one wrapped span.
if t wt_setup_strips_only_one_whole_backtick_span; then setup_repo
commit_setup_line "\`echo a >> $SANDBOX/ticks.log\` && \`echo b >> $SANDBOX/ticks.log\`"
add_wt wt1
cd "$WT"
run start 72 ticks
expect_status 0 "$ST"
expect_not_contains "yntax error"
[ "$(tr '\n' ' ' < "$SANDBOX/ticks.log" 2>/dev/null)" = "a b " ] && ok || fail "the command did not run as written, log: $(cat "$SANDBOX/ticks.log" 2>/dev/null)"
cd "$SANDBOX/work"
commit_setup_line '`echo a` && `echo b`'
add_wt wt2
cd "$WT"
run start 73 ticks
expect_status 2 "$ST"
expect_contains "state=SETUP_FAILED"
expect_not_contains "setup=ran"
fi

# A command sh cannot parse, or cannot find, is a failed setup.
if t wt_setup_unparsable_or_missing_command_fails; then setup_repo
commit_setup_line "echo ("
add_wt wt1
cd "$WT"
run start 74 syntax
expect_status 2 "$ST"
expect_contains "state=SETUP_FAILED"
expect_not_contains "setup=ran"
cd "$SANDBOX/work"
commit_setup_line "no-such-setup-command-gnadd"
add_wt wt2
cd "$WT"
run start 75 missing
expect_status 2 "$ST"
expect_contains "state=SETUP_FAILED"
expect_not_contains "setup=ran"
[ -f "$(git rev-parse --git-dir)/gnadd-setup-done" ] && fail "a failed setup wrote the marker" || ok
fi

if t wt_setup_failure_names_the_branch_even_if_the_command_left_it; then setup_repo
commit_setup_line "git checkout -q --detach; exit 1"
add_wt wt1
cd "$WT"
run start 78 moved
expect_status 2 "$ST"
expect_contains "issue-78/moved is checked out"
expect_contains "rerun 'start 78 moved'"
fi

if t wt_setup_none_in_any_case_runs_nothing; then setup_repo
for NONE_WORD in None NONE '`None`' 'nOnE  '; do
  cd "$SANDBOX/work"
  commit_setup_line "$NONE_WORD"
  add_wt "wt$RANDOM"
  cd "$WT"
  run start 76 none
  expect_status 0 "$ST"
  expect_not_contains "setup"
  git_q -C "$SANDBOX/work" worktree remove --force "$WT"
  git_q -C "$SANDBOX/work" branch -D issue-76/none
done
fi

if t wt_setup_runs_a_line_written_without_a_space; then setup_repo
printf 'Worktree setup:echo tight\n' > AGENTS.md
git_q add AGENTS.md && git_q commit -m "tight line" && git_q push origin main
add_wt wt1
cd "$WT"
run start 77 tight
expect_status 0 "$ST"
expect_contains "  | tight"
run conventions
expect_contains "setup=echo tight"
fi

if t wt_quickfix_start_inside_linked_worktree; then setup_repo
add_wt wt1
WORK_BEFORE="$(folder_snapshot "$SANDBOX/work")"
cd "$WT"
run quickfix start tidy
expect_status 0 "$ST"
expect_contains "branch=quickfix/tidy"
[ "$(git symbolic-ref --short HEAD)" = "quickfix/tidy" ] && ok || fail "not on the quickfix branch"
[ "$(folder_snapshot "$SANDBOX/work")" = "$WORK_BEFORE" ] && ok || fail "the main checkout changed"
fi

if t wt_sync_main_inside_linked_worktree_parks_the_folder; then setup_repo
add_wt wt1
cd "$WT"
run start 31 park
advance_origin_main
MAIN_BEFORE="$(git rev-parse main)"
run sync-main
expect_status 0 "$ST"
expect_contains "synced=true"
expect_contains "parked=true"
git symbolic-ref --quiet HEAD >/dev/null && fail "folder still on a branch after sync-main" || ok
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && ok || fail "folder not parked on origin/main"
[ "$(git rev-parse main)" = "$MAIN_BEFORE" ] && ok || fail "local main moved from inside the worktree"
git show-ref --verify --quiet refs/heads/issue-31/park && ok || fail "sync-main deleted the issue branch"
fi

if t wt_sync_main_inside_linked_worktree_halts_on_diverged_main; then setup_repo
add_wt wt1
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
cd "$WT"
run sync-main
expect_status 2 "$ST"
expect_contains "state=DIVERGED_MAIN"
fi

if t wt_start_resume_of_branch_held_elsewhere_halts_naming_folder; then setup_repo
add_wt wt1
git_q -C "$WT" checkout -b issue-32/held
cd "$SANDBOX/work"
run start 32 held
expect_status 2 "$ST"
expect_contains "state=BRANCH_IN_WORKTREE"
expect_contains "worktree=$WT"
[ "$(git symbolic-ref --short HEAD)" = "main" ] && ok || fail "main checkout moved off main"
fi

if t wt_start_from_branch_held_elsewhere_halts; then setup_repo
add_wt wt1
git_q -C "$WT" checkout -b rescue/there
cd "$SANDBOX/work"
run start 33 rescued --from rescue/there
expect_status 2 "$ST"
expect_contains "state=BRANCH_IN_WORKTREE"
expect_contains "worktree=$WT"
[ "$(git -C "$WT" symbolic-ref --short HEAD)" = "rescue/there" ] && ok || fail "the other folder's branch was renamed"
fi

if t wt_cleanup_and_drop_of_branch_held_elsewhere_halt; then setup_repo
add_wt wt1
git_q -C "$WT" checkout -b issue-34/busy
( cd "$WT" && echo w > w.txt && git_q add w.txt && git_q commit -m w )
cd "$SANDBOX/work"
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-11-09T00:00:00Z
export GH_STUB_PR_HEAD=issue-34/busy GH_STUB_PR_HEAD_OID="$(git rev-parse issue-34/busy)"
run cleanup 70 issue-34/busy
expect_status 2 "$ST"
expect_contains "state=BRANCH_IN_WORKTREE"
expect_contains "worktree=$WT"
run drop issue-34/busy --yes
expect_status 2 "$ST"
expect_contains "state=BRANCH_IN_WORKTREE"
git show-ref --verify --quiet refs/heads/issue-34/busy && ok || fail "deleted a branch another folder holds"
fi

if t wt_rescue_main_from_linked_worktree_halts_before_touching_anything; then setup_repo
add_wt wt1
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
WT_BEFORE="$(folder_snapshot "$WT")"
cd "$WT"
run doctor --rescue-main rescue/stray
expect_status 2 "$ST"
expect_contains "state=BRANCH_IN_WORKTREE"
expect_contains "worktree=$(cd "$SANDBOX/work" && pwd -P)"
git show-ref --verify --quiet refs/heads/rescue/stray && fail "rescue branch created before the halt" || ok
[ "$(folder_snapshot "$WT")" = "$WT_BEFORE" ] && ok || fail "the worktree changed before the halt"
fi

if t wt_two_issues_in_two_worktrees_run_start_to_cleanup; then setup_repo
add_wt wt1; WT1="$WT"
add_wt wt2; WT2="$WT"
WORK_BEFORE="$(folder_snapshot "$SANDBOX/work")"
cd "$WT1"; run start 41 one; expect_status 0 "$ST"
cd "$WT2"; run start 42 two; expect_status 0 "$ST"
cd "$WT1"; echo one > one.txt && git_q add one.txt && git_q commit -m "one"
run round post --changed "slice one" --no-feedback "test"; expect_status 0 "$ST"
WT2_MID="$(folder_snapshot "$WT2")"
run ship push; expect_status 0 "$ST"
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE GH_STUB_CHECKS='test\tpass\t1s\turl'
run ship merge 81; expect_status 0 "$ST"; expect_contains "merged=true"
# Simulate GitHub's squash merge landing on origin/main.
advance_origin_main
run sync-main; expect_status 0 "$ST"; expect_contains "parked=true"
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-11-09T00:00:00Z
export GH_STUB_PR_HEAD=issue-41/one GH_STUB_PR_HEAD_OID="$(git rev-parse issue-41/one)"
run cleanup 81 issue-41/one; expect_status 0 "$ST"; expect_contains "local_deleted=true"
[ "$(folder_snapshot "$WT2")" = "$WT2_MID" ] && ok || fail "issue 41's run changed issue 42's folder"
[ -d "$WT1" ] && ok || fail "cleanup removed the folder"
WT1_DONE="$(folder_snapshot "$WT1")"
cd "$WT2"; echo two > two.txt && git_q add two.txt && git_q commit -m "two"
run round post --changed "slice two" --no-feedback "test"; expect_status 0 "$ST"
run ship push; expect_status 0 "$ST"
export GH_STUB_PR_STATE=OPEN
run ship merge 82; expect_status 0 "$ST"
advance_origin_main
run sync-main; expect_status 0 "$ST"
export GH_STUB_PR_STATE=MERGED GH_STUB_PR_HEAD=issue-42/two GH_STUB_PR_HEAD_OID="$(git rev-parse issue-42/two)"
run cleanup 82 issue-42/two; expect_status 0 "$ST"; expect_contains "local_deleted=true"
[ "$(folder_snapshot "$WT1")" = "$WT1_DONE" ] && ok || fail "issue 42's run changed issue 41's folder"
[ "$(folder_snapshot "$SANDBOX/work")" = "$WORK_BEFORE" ] && ok || fail "the main checkout changed"
# The cleaned-up folder is ready for the next issue.
cd "$WT1"; run start 43 next; expect_status 0 "$ST"; expect_contains "result=created"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] && ok || fail "next issue not built from current origin/main"
fi

if t wt_state_lists_every_issue_in_flight_with_its_folder; then setup_repo
add_wt wt1
git_q -C "$WT" checkout -b issue-51/here
git_q branch issue-52/parked-branch
run state --no-fetch
expect_contains "worktrees=2"
expect_contains "in_flight=issue-51/here folder=$WT"
expect_contains "in_flight=issue-52/parked-branch folder=none"
cd "$WT"
run state --no-fetch
expect_contains "in_flight=issue-51/here folder=$WT"
fi

# A linked folder with nothing in it is named, so one left behind by a
# finished build is seen at the next session start.
if t wt_state_names_an_idle_folder; then setup_repo
add_wt "wt one"
run state --no-fetch
expect_contains "idle_folder=$WT"
cd "$WT"
run state --no-fetch
expect_not_contains "idle_folder="
fi

if t wt_state_does_not_call_a_folder_with_work_idle; then setup_repo
add_wt wt1
echo x > "$WT/untracked.txt"
run state --no-fetch
expect_not_contains "idle_folder="
rm "$WT/untracked.txt"
( cd "$WT" && echo y > c.txt && git_q add c.txt && git_q commit -m "detached work" )
run state --no-fetch
expect_not_contains "idle_folder="
git_q -C "$WT" checkout -b issue-54/busy
run state --no-fetch
expect_not_contains "idle_folder="
fi

if t wt_state_in_single_checkout_has_no_worktree_lines; then setup_repo
git_q branch issue-53/alone
run state --no-fetch
expect_not_contains "worktrees="
expect_not_contains "idle_folder="
expect_not_contains "in_flight="
fi

if t wt_doctor_reports_branches_worktrees_left_behind; then setup_repo
add_wt wt1
git_q -C "$WT" checkout -b issue-61/live
add_wt wt2; GONE="$WT"
git_q -C "$GONE" checkout -b issue-62/orphan
rm -rf "$GONE"
run doctor
expect_contains "finding=WORKTREE_FOLDER_GONE"
expect_contains "branch=issue-62/orphan"
expect_contains "git worktree prune"
expect_not_contains "'issue-61/live' has no commits"
run start 62 orphan
expect_status 2 "$ST"
expect_contains "state=BRANCH_IN_WORKTREE"
expect_contains "git worktree prune"
fi

if t wt_state_reports_a_parked_folder; then setup_repo
add_wt wt1
cd "$WT"
run sync-main
run state --no-fetch
expect_contains "detached=true"
expect_contains "parked=true"
git_q checkout --detach HEAD~0
echo x > p.txt && git_q add p.txt && git_q commit -m "detached work"
run state --no-fetch
expect_not_contains "parked=true"
fi

if t wt_doctor_accepts_a_parked_folder; then setup_repo
add_wt wt1
cd "$WT"
run sync-main
run doctor
expect_not_contains "finding=DETACHED_HEAD"
expect_contains "parked on origin/main"
fi

# A folder stopped mid-rebase or mid-bisect has a detached HEAD, so git's
# worktree path for the branch is empty, yet git still refuses the branch.
if t wt_branch_mid_rebase_in_another_folder_halts_naming_it; then setup_repo
add_wt wt1
( cd "$WT" && git_q checkout -b issue-9/nine
  echo a > a.txt && git_q add a.txt && git_q commit -m a
  echo b > b.txt && git_q add b.txt && git_q commit -m b
  GIT_SEQUENCE_EDITOR="sed -i.bak s/^pick/edit/" git_q rebase -i HEAD~1 )
[ -d "$(git rev-parse --git-common-dir)/worktrees/wt1/rebase-merge" ] && ok || fail "harness: worktree is not mid-rebase"
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-11-09T00:00:00Z
export GH_STUB_PR_HEAD=issue-9/nine GH_STUB_PR_HEAD_OID="$(git rev-parse issue-9/nine)"
run cleanup 3 issue-9/nine
expect_status 2 "$ST"; expect_contains "state=BRANCH_IN_WORKTREE"; expect_contains "worktree=$WT"
expect_contains "mid-rebase or mid-bisect"
run start 9 nine
expect_status 2 "$ST"; expect_contains "state=BRANCH_IN_WORKTREE"; expect_contains "worktree=$WT"
run drop issue-9/nine --yes
expect_status 2 "$ST"; expect_contains "state=BRANCH_IN_WORKTREE"; expect_contains "worktree=$WT"
git show-ref --verify --quiet refs/heads/issue-9/nine && ok || fail "deleted a branch a mid-rebase folder holds"
[ "$(git symbolic-ref --short HEAD)" = "main" ] && ok || fail "main checkout moved off main"
run state --no-fetch
expect_contains "in_flight=issue-9/nine folder=$WT"
# Following the recipe clears it: abort there, then cleanup proceeds.
git_q -C "$WT" rebase --abort
( cd "$WT" && "$GNADD" sync-main >/dev/null 2>&1 )
run cleanup 3 issue-9/nine
expect_status 0 "$ST"; expect_contains "local_deleted=true"
fi

if t wt_branch_mid_bisect_in_another_folder_halts_naming_it; then setup_repo
add_wt wt1
( cd "$WT" && git_q checkout -b issue-9/nine
  for i in 1 2 3 4; do echo "$i" > "f$i.txt"; git_q add "f$i.txt"; git_q commit -m "c$i"; done
  git_q bisect start; git_q bisect bad; git_q bisect good HEAD~4 )
git -C "$WT" symbolic-ref --quiet HEAD >/dev/null && fail "harness: bisect did not detach the worktree" || ok
run start 9 nine
expect_status 2 "$ST"; expect_contains "state=BRANCH_IN_WORKTREE"; expect_contains "worktree=$WT"
run drop issue-9/nine --yes
expect_status 2 "$ST"; expect_contains "state=BRANCH_IN_WORKTREE"
git show-ref --verify --quiet refs/heads/issue-9/nine && ok || fail "deleted a branch a mid-bisect folder holds"
fi

if t wt_parked_folder_without_origin_is_seen_as_parked; then setup_repo
git_q remote remove origin
add_wt wt1
cd "$WT"
run sync-main
expect_status 0 "$ST"; expect_contains "parked=true"
run state
expect_contains "detached=true"
expect_contains "parked=true"
run doctor
expect_not_contains "finding=DETACHED_HEAD"
expect_contains "parked on main"
fi

if t wt_gone_folder_holding_main_gives_only_the_prune_recipe; then setup_repo
git_q checkout --detach
git_q worktree add "$SANDBOX/wtm" main
rm -rf "$SANDBOX/wtm"
HEAD_BEFORE="$(git rev-parse HEAD)"
run doctor
expect_contains "finding=WORKTREE_FOLDER_GONE"
expect_contains "branch=main"
expect_contains "git worktree prune"
expect_not_contains "gnadd cleanup <pr> main"
expect_not_contains "gnadd drop main"
run sync-main
expect_status 2 "$ST"; expect_contains "state=BRANCH_IN_WORKTREE"; expect_contains "git worktree prune"
run start 5 five
expect_status 2 "$ST"; expect_contains "state=BRANCH_IN_WORKTREE"; expect_contains "git worktree prune"
git show-ref --verify --quiet refs/heads/issue-5/five && fail "start cut a branch while main's holder is gone" || ok
[ "$(git rev-parse HEAD)" = "$HEAD_BEFORE" ] && ok || fail "HEAD moved before the halt"
# Following the recipe clears it.
git_q worktree prune
run start 5 five
expect_status 0 "$ST"; expect_contains "result=created"
fi

# Any other git refusal at the resume checkout or a branch delete still halts
# with a named state. A held ref lock makes git refuse without a worktree.
if t git_refusal_at_resume_cleanup_and_drop_halts_with_a_state; then setup_repo
git_q branch issue-7/locked
GD="$(git rev-parse --git-dir)"
: > "$GD/HEAD.lock"
run start 7 locked
rm -f "$GD/HEAD.lock"
expect_status 2 "$ST"; expect_contains "state=CHECKOUT_REFUSED"
[ "$(git symbolic-ref --short HEAD)" = "main" ] && ok || fail "HEAD moved despite the refusal"
mkdir -p "$GD/refs/heads/issue-7" && : > "$GD/refs/heads/issue-7/locked.lock"
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-11-09T00:00:00Z
export GH_STUB_PR_HEAD=issue-7/locked GH_STUB_PR_HEAD_OID="$(git rev-parse issue-7/locked)"
run cleanup 7 issue-7/locked
expect_status 2 "$ST"; expect_contains "state=DELETE_REFUSED"
run drop issue-7/locked --yes
expect_status 2 "$ST"; expect_contains "state=DELETE_REFUSED"
rm -f "$GD/refs/heads/issue-7/locked.lock"
git show-ref --verify --quiet refs/heads/issue-7/locked && ok || fail "branch deleted despite the refusal"
fi

# ---------------------------------------------------------------- test / misc

if t test_detects_makefile; then setup_repo
printf 'test:\n\t@echo make-tests-ran\n' > Makefile
run test
expect_status 0 "$ST"
expect_contains "runner=make"
expect_contains "make-tests-ran"
fi

if t test_no_tests; then setup_repo
run test
expect_status 0 "$ST"
expect_contains "state=NO_TESTS"
fi

if t release_drafts_notes_when_entry_missing; then
# The changelog gate must draft grouped notes from merged-PR history when the
# entry is missing, and still block the release. Runs against the real repo
# read-only: the gate exits before any stamping for a version with no entry.
TREE_BEFORE="$(git -C "$ROOT" status --porcelain)"
OUT="$(bash "$ROOT/scripts/release.sh" v9.9.9 2>&1)"; ST=$?
TREE_AFTER="$(git -C "$ROOT" status --porcelain)"
expect_status 1 "$ST"
expect_contains 'no "## [9.9.9]" entry'
expect_contains "## [9.9.9]"
# Bullets only exist when the range has commits. At a freshly tagged HEAD
# the range is empty and a header-only draft is correct.
REL_LAST_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
REL_COUNT="$(git -C "$ROOT" rev-list --count "${REL_LAST_TAG:+$REL_LAST_TAG..}HEAD" 2>/dev/null || echo 0)"
if [ "$REL_COUNT" -gt 0 ]; then expect_contains "- "; else ok; fi
[ "$TREE_BEFORE" = "$TREE_AFTER" ] && ok || fail "drafting modified the repo working tree"
fi

if t version_reports_channel_baseline; then setup_repo
run version
expect_status 0 "$ST"
expect_contains "gnadd 0."
expect_contains "channel=main"
expect_contains "release baseline"
fi

# ---------------------------------------------------------------- quickfix

if t quickfix_start_creates_branch; then setup_repo
run quickfix start fix-typo
expect_status 0 "$ST"
expect_contains "result=created"
expect_contains "branch=quickfix/fix-typo"
fi

if t quickfix_start_carries_dirty_main; then setup_repo
echo tweak >> README.md
run quickfix start doc-tweak --carry
expect_status 0 "$ST"
expect_contains "result=created-carry"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main was modified by carry"
fi

if t quickfix_start_refuses_existing_branch; then setup_repo
git_q branch quickfix/dup
run quickfix start dup
expect_status 2 "$ST"
expect_contains "state=QF_BRANCH_EXISTS"
fi

if t quickfix_start_halts_on_diverged_main; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
run quickfix start anything
expect_status 2 "$ST"
expect_contains "state=DIVERGED_MAIN"
fi

if t quickfix_guard_small_change_ok; then setup_repo
run quickfix start small
echo tweak >> README.md && git_q add README.md && git_q commit -m "tweak"
run quickfix guard
expect_status 0 "$ST"
expect_contains "guard=ok"
expect_contains "files=1"
fi

if t quickfix_guard_refuses_too_many_lines; then setup_repo
run quickfix start big
seq 1 40 > big.txt && git_q add big.txt && git_q commit -m "big"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=TOO_BIG"
fi

if t quickfix_guard_exempts_new_vision_md; then setup_repo
run quickfix start vision
seq 1 45 | sed 's/^/vision line /' > VISION.md && git_q add VISION.md && git_q commit -m "vision"
run quickfix guard
expect_status 0 "$ST"
expect_contains "guard=ok"
expect_contains "exempt=VISION.md"
expect_contains "lines=0"
# The exemption does not leak to other files in the same diff.
seq 1 40 > big.txt && git_q add big.txt && git_q commit -m "big"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=TOO_BIG"
fi

if t quickfix_guard_counts_modified_vision_md; then setup_repo
seq 1 5 > VISION.md && git_q add VISION.md && git_q commit -m "vision" && git_q push origin main
run quickfix start revise-vision
seq 1 45 > VISION.md && git_q add VISION.md && git_q commit -m "rewrite"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=TOO_BIG"
expect_not_contains "exempt="
fi

if t quickfix_guard_refuses_too_many_files; then setup_repo
run quickfix start wide
for f in a b c d; do echo x > "$f.txt"; done
git_q add . && git_q commit -m "wide"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=TOO_BIG"
fi

if t quickfix_guard_refuses_protected_paths; then setup_repo
run quickfix start sneaky
mkdir -p scripts && echo x > scripts/hack.sh
git_q add . && git_q commit -m "sneaky"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=PROTECTED_PATH"
fi

if t quickfix_guard_refuses_gnadd_copies; then setup_repo
run quickfix start copy-edit
mkdir -p skills/foo && echo x > skills/foo/gnadd.sh
git_q add . && git_q commit -m "copy edit"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=PROTECTED_PATH"
fi

if t quickfix_ship_happy; then setup_repo
run quickfix start shippable
echo tweak >> README.md && git_q add README.md && git_q commit -m "tweak"
run quickfix ship
expect_status 0 "$ST"
expect_contains "guard=ok"
expect_contains "pushed=true"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main gained a commit"
fi

if t quickfix_ship_refuses_non_quickfix_branch; then setup_repo
git_q checkout -b issue-20/not-quickfix
run quickfix ship
expect_status 2 "$ST"
expect_contains "state=NOT_QUICKFIX_BRANCH"
fi

if t quickfix_merge_waits_for_ci; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='test\tpending\t0\turl'
run quickfix merge 50
expect_status 2 "$ST"
expect_contains "state=QF_CHECKS_PENDING"
expect_gh_not_called "pr merge" "merged with CI still pending"
fi

if t quickfix_merge_refuses_failed_ci; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='test\tfail\t5s\turl'
run quickfix merge 50
expect_status 2 "$ST"
expect_contains "state=QF_CHECK_FAILED"
expect_gh_not_called "pr merge" "merged despite failing CI"
fi

if t quickfix_merge_after_green_ci; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='CodeRabbit\tfail\t0\turl\ntest\tpass\t5s\turl'
run quickfix merge 50
expect_status 0 "$ST"
expect_contains "check_status=pass"
expect_contains "merged=true"
expect_gh_called "pr merge 50 --squash" "gh pr merge --squash not called"
fi

if t quickfix_merge_refuses_when_no_checks; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
run quickfix merge 50
expect_status 2 "$ST"
expect_contains "state=QF_NO_CHECKS"
run quickfix merge 50 --no-check
expect_status 0 "$ST"
expect_contains "merged=true"
fi

if t quickfix_merge_unknown_check_name; then setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='ci-build\tpass\t5s\turl'
run quickfix merge 50
expect_status 2 "$ST"
expect_contains "state=QF_CHECK_NOT_FOUND"
run quickfix merge 50 --check ci-build
expect_status 0 "$ST"
expect_contains "merged=true"
fi

# ---------------------------------------------------------------- trace

if t trace_records_each_invocation; then setup_repo
run state
run guard-commit
run trace show
expect_status 0 "$ST"
expect_contains "gnadd state status=0"
expect_contains "gnadd guard-commit status=2"
fi

if t trace_reset_and_meta_commands_leave_no_lines; then setup_repo
run state
run trace reset
run version
run trace show
expect_status 0 "$ST"
expect_contains "trace=empty"
fi

if t trace_note_records_a_step_outside_the_script; then setup_repo
run trace note gh pr create --draft
expect_status 0 "$ST"
expect_contains "trace=noted"
run trace show
expect_contains " note gh pr create --draft branch=main"
run trace note
expect_status 1 "$ST"
fi

if t trace_survives_midpipe_kill; then setup_repo
# Killing a run mid-pipe (reader closes early → SIGPIPE) must not garble the
# trace: bash 3.2 flushes the stdout it failed to write into the trace line
# (issue #38). Each killed run must leave at most one well-formed line.
for i in 1 2 3 4 5; do
  "$GNADD" state --no-fetch 2>/dev/null | head -1 >/dev/null
done
TRACE_LINES="$(wc -l < .git/gnadd-trace.log | tr -d ' ')"
[ "$TRACE_LINES" -le 5 ] && ok || fail "expected at most 5 trace lines, got $TRACE_LINES: $(cat .git/gnadd-trace.log)"
if grep -Evq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z gnadd state --no-fetch status=[0-9]+ branch=main$' .git/gnadd-trace.log; then
  fail "malformed trace line after mid-pipe kill: $(cat .git/gnadd-trace.log)"
else
  ok
fi
fi

if t trace_stays_out_of_working_tree; then setup_repo
run state
[ -z "$(git status --porcelain)" ] && ok || fail "trace log dirtied the working tree"
[ -f .git/gnadd-trace.log ] && ok || fail "trace log not written to .git/"
fi

# ---------------------------------------------------------------- push

if t push_sets_upstream_and_never_forces; then setup_repo
run start 40 checkpoint
echo a > a.txt && git_q add a.txt && git_q commit -m "slice"
run push
expect_status 0 "$ST"
expect_contains "pushed=true"
expect_contains "upstream=origin/issue-40/checkpoint"
git ls-remote --exit-code --heads origin issue-40/checkpoint >/dev/null 2>&1 && ok || fail "branch not on remote"
# Second push with a new commit: plain fast-forward.
echo b > b.txt && git_q add b.txt && git_q commit -m "slice two"
run push
expect_status 0 "$ST"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/issue-40/checkpoint)" ] && ok || fail "second push did not land"
# Remote moved on without us: refuse, do not force.
( cd "$SANDBOX" && git_q clone origin.git other5 && cd other5
  git config user.email o@o && git config user.name o
  git_q checkout issue-40/checkpoint
  echo remote >> r.txt && git_q add r.txt && git_q commit -m "remote work"
  git_q push origin issue-40/checkpoint )
remote_sha="$(git ls-remote origin refs/heads/issue-40/checkpoint | cut -f1)"
echo c > c.txt && git_q add c.txt && git_q commit -m "local work"
run push
expect_status 2 "$ST"
expect_contains "state=PUSH_FAILED"
[ "$(git ls-remote origin refs/heads/issue-40/checkpoint | cut -f1)" = "$remote_sha" ] && ok || fail "remote branch was overwritten"
fi

if t push_refuses_main; then setup_repo
run push
expect_status 2 "$ST"
expect_contains "state=ON_MAIN"
fi

if t push_without_remote_reports; then setup_repo
run start 41 offline
git_q remote remove origin
echo a > a.txt && git_q add a.txt && git_q commit -m "slice"
run push
expect_status 0 "$ST"
expect_contains "pushed=false"
expect_contains "upstream=none"
fi

# ---------------------------------------------------------------- round

if t round_post_pushes_before_commenting; then setup_repo
run start 42 rounds-push
echo a > a.txt && git_q add a.txt && git_q commit -m "slice one"
export GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round post --changed "first slice" --feedback "fine"
expect_status 0 "$ST"
expect_contains "pushed=true"
expect_contains "posted=true"
git ls-remote --exit-code --heads origin issue-42/rounds-push >/dev/null 2>&1 && ok || fail "checkpoint not on remote after round post"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/issue-42/rounds-push)" ] && ok || fail "cited sha not on origin"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "Commit: \`$(git rev-parse --short HEAD)\`"
fi

if t round_post_halts_when_push_refused; then setup_repo
run start 43 rounds-halt
echo a > a.txt && git_q add a.txt && git_q commit -m "slice one"
run push
( cd "$SANDBOX" && git_q clone origin.git other6 && cd other6
  git config user.email o@o && git config user.name o
  git_q checkout issue-43/rounds-halt
  echo remote >> r.txt && git_q add r.txt && git_q commit -m "remote work"
  git_q push origin issue-43/rounds-halt )
echo b > b.txt && git_q add b.txt && git_q commit -m "local work"
export GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round post --changed "second slice" --feedback "ok"
expect_status 2 "$ST"
expect_contains "state=PUSH_FAILED"
expect_not_contains "posted=true"
[ -f "$SANDBOX/comment.md" ] && fail "comment posted despite refused push" || ok
fi

if t round_post_without_remote_still_posts; then setup_repo
run start 44 rounds-offline
git_q remote remove origin
echo a > a.txt && git_q add a.txt && git_q commit -m "slice one"
export GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round post --changed "slice" --no-feedback "nothing to try"
expect_status 0 "$ST"
expect_contains "pushed=false"
expect_contains "posted=true"
fi

if t round_post_first_round; then setup_repo
run start 5 rounds
echo a > a.txt && git_q add a.txt && git_q commit -m "slice one"
export GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round post --changed "first slice" --feedback "looks good, make the button bluer"
expect_status 0 "$ST"
expect_contains "issue=5"
expect_contains "round=1"
expect_contains "posted=true"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "<!-- gnadd:round -->"
expect_contains "## Round 1"
expect_contains "**Changed:** first slice"
expect_contains "transcribed by the agent from chat"
expect_contains "> looks good, make the button bluer"
expect_gh_called "gh issue comment 5 --body-file" "comment not posted via gh issue comment"
fi

if t round_post_numbers_from_record; then setup_repo
run start 6 rounds
export GH_STUB_ROUND_COUNT=2 GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round post --changed "third slice" --feedback "ok"
expect_status 0 "$ST"
expect_contains "round=3"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "## Round 3"
fi

if t round_post_feedback_file_verbatim; then setup_repo
run start 7 rounds
export GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
printf 'teh spacing is off\nand also the font\n' > "$SANDBOX/fb.txt"
run round post --changed "spacing" --feedback-file "$SANDBOX/fb.txt"
expect_status 0 "$ST"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "> teh spacing is off"
expect_contains "> and also the font"
fi

if t round_post_no_feedback_is_explicit; then setup_repo
run start 8 rounds
export GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round post --changed "scaffold" --no-feedback "first slice, nothing to try yet"
expect_status 0 "$ST"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "**Feedback:** none this round (first slice, nothing to try yet)."
expect_not_contains "transcribed"
fi

if t round_post_refuses_empty_feedback; then setup_repo
run start 9 rounds
run round post --changed "x"
expect_status 1 "$ST"
expect_contains "never inferred"
run round post --changed "x" --feedback ""
expect_status 1 "$ST"
expect_contains "feedback text is empty"
run round post --changed "x" --feedback "a" --no-feedback "b"
expect_status 1 "$ST"
expect_gh_not_called "issue comment" "posted despite refusal"
fi

if t round_post_refuses_non_issue_branch; then setup_repo
run round post --changed "x" --feedback "y"
expect_status 2 "$ST"
expect_contains "state=NOT_ISSUE_BRANCH"
git_q checkout -b quickfix/typo
run round post --changed "x" --feedback "y"
expect_status 2 "$ST"
expect_contains "state=NOT_ISSUE_BRANCH"
expect_gh_not_called "issue comment" "posted off an issue branch"
fi

if t round_list_in_order; then setup_repo
run start 10 rounds
export GH_STUB_ROUND_COUNT=2
export GH_STUB_ROUND_BODIES='<!-- gnadd:round -->\n## Round 1\n\n**Changed:** a\n<!-- gnadd:round -->\n## Round 2\n\n**Changed:** b'
run round list
expect_status 0 "$ST"
expect_contains "issue=10"
expect_contains "rounds=2"
expect_not_contains "gnadd:round"
case "$OUT" in *"Round 1"*"Round 2"*) ok ;; *) fail "rounds out of order: $OUT" ;; esac
fi

if t round_feedback_posts_without_commit; then setup_repo
run start 12 rounds
export GH_STUB_ROUND_COUNT=2 GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round feedback --feedback "good, but the header wraps"
expect_status 0 "$ST"
expect_contains "issue=12"
expect_contains "round=2"
expect_contains "posted=true"
expect_not_contains "pushed="
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "<!-- gnadd:feedback -->"
expect_contains "## Round 2 feedback"
expect_contains "transcribed by the agent from chat"
expect_contains "> good, but the header wraps"
expect_gh_called "gh issue comment 12 --body-file" "feedback not posted via gh issue comment"
git ls-remote --exit-code --heads origin issue-12/rounds >/dev/null 2>&1 && fail "round feedback pushed the branch" || ok
fi

if t round_feedback_file_and_none; then setup_repo
run start 13 rounds
export GH_STUB_ROUND_COUNT=1 GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
printf 'ship it\n' > "$SANDBOX/fb.txt"
run round feedback --feedback-file "$SANDBOX/fb.txt"
expect_status 0 "$ST"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "> ship it"
run round feedback --no-feedback "user stepped away"
expect_status 0 "$ST"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "**Feedback:** none this round (user stepped away)."
fi

if t round_feedback_refuses_without_a_round; then setup_repo
run start 14 rounds
run round feedback --feedback "nice"
expect_status 2 "$ST"
expect_contains "state=NO_ROUNDS"
expect_gh_not_called "issue comment" "feedback posted with no round to answer"
fi

if t round_feedback_refuses_duplicate; then setup_repo
run start 15 rounds
export GH_STUB_ROUND_COUNT=1 GH_STUB_ROUND_LAST=feedback
run round feedback --feedback "again"
expect_status 2 "$ST"
expect_contains "state=FEEDBACK_RECORDED"
expect_gh_not_called "issue comment" "duplicate feedback posted"
fi

if t round_feedback_refuses_empty_and_off_branch; then setup_repo
run round feedback --feedback "x"
expect_status 2 "$ST"
expect_contains "state=NOT_ISSUE_BRANCH"
run start 16 rounds
export GH_STUB_ROUND_COUNT=1
run round feedback
expect_status 1 "$ST"
expect_contains "never inferred"
run round feedback --feedback ""
expect_status 1 "$ST"
expect_contains "feedback text is empty"
run round feedback --feedback "a" --no-feedback "b"
expect_status 1 "$ST"
expect_gh_not_called "issue comment" "posted despite refusal"
fi

if t round_post_cites_recorded_feedback; then setup_repo
run start 17 rounds
echo a > a.txt && git_q add a.txt && git_q commit -m "slice two"
export GH_STUB_ROUND_COUNT=1 GH_STUB_ROUND_LAST=feedback GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round post --changed "second slice"
expect_status 0 "$ST"
expect_contains "round=2"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "**Feedback:** recorded on round 1."
expect_not_contains "transcribed"
fi

if t round_post_refuses_feedback_already_recorded; then setup_repo
run start 18 rounds
echo a > a.txt && git_q add a.txt && git_q commit -m "slice two"
export GH_STUB_ROUND_COUNT=1 GH_STUB_ROUND_LAST=feedback
run round post --changed "second slice" --feedback "ok"
expect_status 1 "$ST"
expect_contains "already on the record"
expect_gh_not_called "issue comment" "duplicate feedback carried into round post"
fi

if t round_post_still_requires_feedback_when_unrecorded; then setup_repo
run start 19 rounds
export GH_STUB_ROUND_COUNT=1 GH_STUB_ROUND_LAST=round
run round post --changed "second slice"
expect_status 1 "$ST"
expect_contains "never inferred"
fi

if t round_list_includes_feedback; then setup_repo
run start 20 rounds
export GH_STUB_ROUND_COUNT=1
export GH_STUB_ROUND_BODIES='<!-- gnadd:round -->\n## Round 1\n\n**Changed:** a\n<!-- gnadd:feedback -->\n## Round 1 feedback\n\n> ship it'
run round list
expect_status 0 "$ST"
expect_contains "rounds=1"
expect_not_contains "gnadd:feedback"
case "$OUT" in *"Round 1"*"Round 1 feedback"*"> ship it"*) ok ;; *) fail "feedback missing from round list: $OUT" ;; esac
fi

if t round_list_none; then setup_repo
run round list 11
expect_status 0 "$ST"
expect_contains "rounds=0"
fi

# ---------------------------------------------------------------- question


if t question_ask_comments_and_assigns_on_the_item; then setup_repo; q_reset
run question ask --to @alex --on 5 --question "Cache or recompute?" --options "1. cache 2. recompute" --recommend "1, reads dominate"
expect_status 0 "$ST"
expect_contains "item=5"
expect_contains "question=1"
expect_contains "created_issue=false"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 1 to=alex assigned=added -->"
expect_contains "**Question:** Cache or recompute?"
expect_contains "1. cache 2. recompute"
expect_contains "**Recommendation:** 1, reads dominate"
expect_gh_called "api repos/{owner}/{repo}/issues/5/comments -F body=@" "question not posted as a comment on the item"
expect_gh_called "api -X POST repos/{owner}/{repo}/issues/5/assignees -f assignees\[\]=alex" "item not assigned to the named person"
expect_gh_not_called "issue create" "an issue was created for a question that has an item"
expect_gh_not_called "label" "a label was used for a question that has an item"
fi

# Enough other assignees after the named one to outlast a pipe buffer: a
# check that stops reading at the first match makes gh's writes fail.
if t question_ask_with_other_assignees; then setup_repo; q_reset
export GH_STUB_OTHER_ASSIGNEES=6000
run question ask --to alex --on 5 --question q --options o --recommend r
expect_status 0 "$ST"
expect_contains "posted=true"
expect_not_contains "ASSIGN_FAILED"
fi

if t question_ask_records_an_existing_assignment; then setup_repo; q_reset
export GH_STUB_ITEM_META='open\tAlex bob'
run question ask --to alex --on 5 --question q --options o --recommend r
expect_status 0 "$ST"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 1 to=alex assigned=existing -->"
expect_gh_not_called "X POST" "re-assigned someone who was already assigned"
fi

if t question_ask_records_an_added_assignment; then setup_repo; q_reset
run question ask --to alex --on 5 --question q --options o --recommend r
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 1 to=alex assigned=added -->"
fi

# The first question's ask assigned alex, so the second finds him assigned.
# It must not read that as an assignment that was there before the questions.
if t question_ask_copies_added_from_an_open_question_to_the_same_person; then setup_repo; q_reset
export GH_STUB_ITEM_META='open\tAlex'
export GH_STUB_QROWS='comment\tq\t1\tALEX\tadded\tfirst'
run question ask --to alex --on 5 --question "second?" --options o --recommend r
expect_status 0 "$ST"
expect_contains "question=2"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 2 to=alex assigned=added -->"
expect_gh_not_called "X POST" "re-assigned someone the first question already assigned"
fi

# A follow-up after an answer: question 1 is answered but not closed, so it is
# still open and still settles whose assignment this is.
if t question_ask_copies_added_from_an_answered_open_question; then setup_repo; q_reset
export GH_STUB_ITEM_META='open\talex'
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tfirst\ncomment\treply'
run question ask --to alex --on 5 --question "second?" --options o --recommend r
expect_status 0 "$ST"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 2 to=alex assigned=added -->"
fi

if t question_ask_copies_existing_from_an_open_question_to_the_same_person; then setup_repo; q_reset
export GH_STUB_ITEM_META='open\talex'
export GH_STUB_QROWS='comment\tq\t1\talex\texisting\tfirst\ncomment\treply'
run question ask --to alex --on 5 --question "second?" --options o --recommend r
expect_status 0 "$ST"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 2 to=alex assigned=existing -->"
fi

# The owner was assigned before question 1, someone took the assignment off by
# hand, and question 2 puts it back: it is still not the questions' to remove.
if t question_ask_reassigns_but_copies_existing; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\texisting\tfirst'
run question ask --to alex --on 5 --question "second?" --options o --recommend r
expect_status 0 "$ST"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 2 to=alex assigned=existing -->"
expect_gh_called "api -X POST repos/{owner}/{repo}/issues/5/assignees -f assignees\[\]=alex" "item not assigned to the named person"
fi

# A closed question settles nothing for a later one, and neither does an open
# question to somebody else: alex is assigned and no open question put him there.
if t question_ask_copies_nothing_from_closed_or_other_peoples_questions; then setup_repo; q_reset
export GH_STUB_ITEM_META='open\talex bob'
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tfirst\ncomment\treply\ncomment\tc\t1\ncomment\tq\t2\tbob\tadded\tsecond'
run question ask --to alex --on 5 --question "third?" --options o --recommend r
expect_status 0 "$ST"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 3 to=alex assigned=existing -->"
fi

# After question 1 closed and took the assignment with it, a later ask adds it again.
if t question_ask_adds_again_after_an_unassigning_close; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tfirst\ncomment\treply\ncomment\tc\t1'
run question ask --to alex --on 5 --question "second?" --options o --recommend r
expect_status 0 "$ST"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 2 to=alex assigned=added -->"
expect_gh_called "api -X POST repos/{owner}/{repo}/issues/5/assignees -f assignees\[\]=alex" "item not assigned again"
fi

if t question_ask_halts_when_the_item_cannot_be_read; then setup_repo; q_reset
export GH_STUB_ITEM_READ_FAIL=1
run question ask --to alex --on 5 --question q --options o --recommend r
expect_status 2 "$ST"
expect_contains "state=QUESTION_READ_FAILED"
expect_contains "could not read #5"
expect_gh_not_called "comments -F" "asked on an item that could not be read"
expect_gh_not_called "X POST" "assigned an item that could not be read"
fi

if t question_ask_halts_when_the_comments_cannot_be_read; then setup_repo; q_reset
export GH_STUB_QREAD_FAIL=1
run question ask --to alex --on 5 --question q --options o --recommend r
expect_status 2 "$ST"
expect_contains "state=QUESTION_READ_FAILED"
expect_contains "could not read the comments on #5"
expect_gh_not_called "comments -F" "asked without the record to number the question from"
expect_gh_not_called "X POST" "assigned an item whose comments could not be read"
fi

if t question_ask_halts_on_a_closed_item; then setup_repo; q_reset
export GH_STUB_ITEM_META='closed\t'
run question ask --to alex --on 5 --question q --options o --recommend r
expect_status 2 "$ST"
expect_contains "state=ITEM_CLOSED"
expect_gh_not_called "comments -F" "asked on a closed item, where list can never show it"
fi

if t question_ask_numbers_from_the_record; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tfirst\ncomment\tc\t1\ncomment\tq\t2\talex\tadded\tsecond'
run question ask --to alex --on 5 --question "third?" --options "a/b" --recommend "a"
expect_status 0 "$ST"
expect_contains "question=3"
fi

if t question_ask_without_an_item_opens_a_question_issue; then setup_repo; q_reset
export GH_STUB_ISSUE_NUMBER=31
run question ask --to alex --title "Which license?" --question "MIT or Apache?" --options "1. MIT 2. Apache" --recommend "MIT"
expect_status 0 "$ST"
expect_contains "item=31"
expect_contains "created_issue=true"
expect_gh_called "issue create --title Which license? --body-file .* --label question --assignee alex" "question issue not created with the question label and assignee"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question 1 to=alex assigned=added -->"
fi

if t question_ask_refusals; then setup_repo; q_reset
run question ask --on 5 --question q --options o --recommend r
expect_status 1 "$ST"; expect_contains "--to <login>"
run question ask --to alex --question q --options o --recommend r
expect_status 1 "$ST"; expect_contains "--on <issue-or-pr>"
run question ask --to alex --on 5 --title t --question q --options o --recommend r
expect_status 1 "$ST"; expect_contains "not both"
run question ask --to alex --on 5 --question q --recommend r
expect_status 1 "$ST"; expect_contains "--options"
run question ask --to alex --on 5 --question q --options o
expect_status 1 "$ST"; expect_contains "--recommend"
expect_gh_not_called "comments -F" "a refused question was posted"
fi

if t question_ask_halts_when_assignment_is_dropped; then setup_repo; q_reset
export GH_STUB_ASSIGN_IGNORED=1
run question ask --to nobody --on 5 --question q --options o --recommend r
expect_status 2 "$ST"
expect_contains "state=ASSIGN_FAILED"
expect_contains "do not re-ask"
fi

# The stub feeds classified rows, so the classifier itself (gnadd's qrow jq,
# which gh runs) is checked here against comment JSON from one shared
# account, with system jq standing in for gh's. Skipped where jq is absent.
if t question_classifier_reads_markers_not_authors; then
if command -v jq >/dev/null 2>&1; then
  eval "$(sed -n "/^QUESTION_JQ_DEF=/,/end;'\$/p" "$GNADD")"
  OUT="$(printf '%s' '[{"user":{"login":"me","type":"User"},"body":"the spec"},
    {"user":{"login":"me","type":"User"},"body":"<!-- gnadd:question 2 to=alex -->\n## Question 2 for @alex\n\n**Question:** Cache or recompute?\n\n**Options:** a"},
    {"user":{"login":"coderabbitai[bot]","type":"Bot"},"body":"Walkthrough"},
    {"user":{"login":"me","type":"User"},"body":"<!-- gnadd:round -->\n## Round 3"},
    {"user":{"login":"me","type":"User"},"body":"<!-- gnadd:answer 2 -->\n> cache"},
    {"user":{"login":"me","type":"User"},"body":"<!-- gnadd:question-closed 2 -->\ndone"},
    {"user":{"login":"me","type":"User"},"body":"cache it"},
    {"user":{"login":"me","type":"User"},"body":"<!-- gnadd:answer 2 -->\n> as asked in <!-- gnadd:question 7 to=bob -->"},
    {"user":{"login":"me","type":"User"},"body":"<!-- gnadd:question-closed 2 -->\n**Acted on:** quoted <!-- gnadd:answer 1 --> by hand"},
    {"user":{"login":"me","type":"User"},"body":"yes, and I saw <!-- gnadd:round --> in the log"},
    {"user":{"login":"me","type":"User"},"body":"<!-- gnadd:question 3 to=bob assigned=existing -->\n**Question:** Own issue?"}]' \
    | jq -r "$QUESTION_JQ_DEF .[] | qrow" | tr '\t' ' ' | tr '\n' '|')"
  [ "$OUT" = "reply|q 2 alex added Cache or recompute?|other|other|a 2|c 2|reply|a 2|c 2|reply|q 3 bob existing Own issue?|" ] && ok \
    || fail "qrow misclassified the thread: $OUT"
else
  ok; printf 'skip %s: jq not installed\n' "$CURRENT"
fi
fi

# Every row below comes from one shared account: only markers tell the
# agent's comments from the person's reply, and a bot's comment is no answer.
if t question_list_separates_answered_from_unanswered; then setup_repo; q_reset
export GH_STUB_OPEN_ITEMS='5\tissue\tCaching\n6\tpr\tAdd cache\n7\tissue\tLicense'
export GH_STUB_QROWS_5='comment\tq\t1\talex\tadded\tCache or recompute?\ncomment\tother\ncomment\treply'
export GH_STUB_QROWS_6='comment\tq\t1\talex\tadded\tShip behind a flag?\ncomment\tother'
export GH_STUB_QROWS_7='comment\tq\t1\talex\tadded\tMIT?\ncomment\ta\t1\ncomment\tq\t2\talex\tadded\tYear?\ncomment\tq\t3\talex\tadded\tDone one\ncomment\treply\ncomment\tc\t3'
run question list
expect_status 0 "$ST"
expect_contains "questions=4"
expect_contains "answered=3"
expect_contains "unanswered=1"
expect_contains "question item=5 number=1 status=answered to=alex kind=issue"
expect_contains "question item=6 number=1 status=unanswered to=alex kind=pr"
expect_contains "question item=7 number=1 status=answered"
expect_contains "question item=7 number=2 status=answered"
expect_not_contains "number=3"
case "$OUT" in *"status=answered"*"status=unanswered"*) ok ;; *) fail "answered not listed before unanswered: $OUT" ;; esac
expect_gh_called "issues?state=open" "open items not read"
fi

if t question_list_bot_comment_is_not_an_answer; then setup_repo; q_reset
export GH_STUB_OPEN_ITEMS='6\tpr\tAdd cache'
export GH_STUB_QROWS_6='comment\tq\t1\talex\tadded\tFlag?\ncomment\tother'
run question list
expect_contains "unanswered=1"
expect_contains "answered=0"
fi

if t question_list_none; then setup_repo; q_reset
run question list
expect_status 0 "$ST"
expect_contains "questions=0"
fi

if t question_answer_records_a_transcribed_answer; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tCache or recompute?'
run question answer 5 --answer "cache it, recompute is too slow"
expect_status 0 "$ST"
expect_contains "question=1"
expect_contains "status=answered"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:answer 1 -->"
expect_contains "transcribed by the agent from chat"
expect_contains "> cache it, recompute is too slow"
fi

if t question_answer_refusals; then setup_repo; q_reset
run question answer 5 --answer "x"
expect_status 2 "$ST"; expect_contains "state=NO_OPEN_QUESTION"
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tA?\ncomment\tq\t2\talex\tadded\tB?'
run question answer 5 --answer "x"
expect_status 1 "$ST"; expect_contains "several open questions"
run question answer 5 2 --answer ""
expect_status 1 "$ST"; expect_contains "empty"
expect_gh_not_called "comments -F" "a refused answer was posted"
run question answer 5 2 --answer "B it is"
expect_status 0 "$ST"; expect_contains "question=2"
fi

if t question_close_says_so_and_unassigns; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tCache?\ncomment\treply'
run question close 5 --acted "cached in round 2"
expect_status 0 "$ST"
expect_contains "status=closed"
expect_contains "unassigned=true"
expect_contains "closed_issue=false"
OUT="$(cat "$GH_STUB_COMMENT_FILE")"
expect_contains "<!-- gnadd:question-closed 1 -->"
expect_contains "**Acted on:** cached in round 2"
expect_gh_called "api -X DELETE repos/{owner}/{repo}/issues/5/assignees -f assignees\[\]=alex" "assignment not removed"
expect_gh_not_called "issue close" "an ordinary item was closed"
fi

if t question_close_keeps_assignment_another_question_needs; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tA?\ncomment\tq\t2\talex\tadded\tB?\ncomment\ta\t1'
run question close 5 1 --acted "did A"
expect_status 0 "$ST"
expect_contains "unassigned=false"
expect_gh_not_called "X DELETE" "assignment removed while question 2 still needs it"
fi

if t question_close_closes_a_question_issue; then setup_repo; q_reset
export GH_STUB_QBODY='body\tq\t1\talex\tadded\tMIT?' GH_STUB_QROWS='comment\treply'
run question close 31 --acted "licensed MIT"
expect_status 0 "$ST"
expect_contains "closed_issue=true"
expect_gh_called "issue close 31" "question issue left open after it was acted on"
fi

if t question_close_keeps_an_assignment_ask_did_not_add; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\texisting\tOwn?\ncomment\treply'
run question close 5 --acted "done"
expect_status 0 "$ST"
expect_contains "unassigned=false"
expect_gh_not_called "X DELETE" "removed an assignment that was there before the question"
fi

if t question_close_compares_logins_case_insensitively; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\tAlex\tadded\tA?\ncomment\tq\t2\talex\tadded\tB?\ncomment\ta\t1'
run question close 5 1 --acted "did A"
expect_status 0 "$ST"
expect_contains "unassigned=false"
expect_gh_not_called "X DELETE" "assignment removed while question 2 (same login, other case) needs it"
fi

if t question_close_closes_question_issue_whichever_was_last; then setup_repo; q_reset
export GH_STUB_QBODY='body\tq\t1\talex\tadded\tMIT?' GH_STUB_QROWS='comment\tc\t1\ncomment\tq\t2\talex\tadded\tYear?\ncomment\treply'
run question close 31 --acted "set the year"
expect_status 0 "$ST"
expect_contains "question=2"
expect_contains "closed_issue=true"
expect_gh_called "issue close 31" "question issue left open after its last question closed"
fi

if t question_close_closes_the_issue_before_unassigning; then setup_repo; q_reset
export GH_STUB_QBODY='body\tq\t1\talex\tadded\tMIT?' GH_STUB_QROWS='comment\treply' GH_STUB_UNASSIGN_FAIL=1
run question close 31 --acted "licensed MIT"
expect_status 2 "$ST"
expect_contains "state=UNASSIGN_FAILED"
expect_gh_called "issue close 31" "the unassign halt left the question issue open"
fi

# Two questions to one person, both from asks that own the assignment, closed
# in ask order: the second close is the last one and removes it.
if t question_close_unassigns_with_the_last_of_several_in_ask_order; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tA?\ncomment\tq\t2\talex\tadded\tB?\ncomment\treply\ncomment\tc\t1'
run question close 5 2 --acted "did B"
expect_status 0 "$ST"
expect_contains "unassigned=true"
expect_gh_called "api -X DELETE repos/{owner}/{repo}/issues/5/assignees -f assignees\[\]=alex" "assignment left behind by the last question"
fi

if t question_close_unassigns_with_the_last_of_several_in_reverse_order; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tA?\ncomment\tq\t2\talex\tadded\tB?\ncomment\treply\ncomment\tc\t2'
run question close 5 1 --acted "did A"
expect_status 0 "$ST"
expect_contains "unassigned=true"
fi

if t question_close_keeps_another_persons_assignment; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tA?\ncomment\tq\t2\tbob\tadded\tB?\ncomment\treply'
run question close 5 1 --acted "did A"
expect_status 0 "$ST"
expect_contains "unassigned=true"
expect_gh_called "api -X DELETE repos/{owner}/{repo}/issues/5/assignees -f assignees\[\]=alex" "alex kept though his only question closed"
expect_gh_not_called "assignees\[\]=bob" "bob unassigned while his question is open"
fi

if t question_close_halts_when_the_issue_will_not_close; then setup_repo; q_reset
export GH_STUB_QBODY='body\tq\t1\talex\tadded\tMIT?' GH_STUB_QROWS='comment\treply' GH_STUB_ISSUE_CLOSE_FAIL=1
run question close 31 --acted "licensed MIT"
expect_status 2 "$ST"
expect_contains "state=ISSUE_CLOSE_FAILED"
expect_contains "close it by hand"
expect_not_contains "remove @alex"
expect_not_contains "status=closed"
expect_gh_called "issues/31/comments -F body=@" "the closing comment was not posted"
expect_gh_called "api -X DELETE repos/{owner}/{repo}/issues/31/assignees -f assignees\[\]=alex" "the failed issue close skipped the unassign"
fi

if t question_close_halts_once_when_close_and_unassign_both_fail; then setup_repo; q_reset
export GH_STUB_QBODY='body\tq\t1\talex\tadded\tMIT?' GH_STUB_QROWS='comment\treply' GH_STUB_ISSUE_CLOSE_FAIL=1 GH_STUB_UNASSIGN_FAIL=1
run question close 31 --acted "licensed MIT"
expect_status 2 "$ST"
expect_contains "state=ISSUE_CLOSE_FAILED"
expect_contains "close it by hand and remove @alex from it"
expect_not_contains "state=UNASSIGN_FAILED"
expect_not_contains "status=closed"
fi

if t question_answer_and_close_refuse_non_numeric_items; then setup_repo; q_reset
run question answer "5/../6" --answer x
expect_status 1 "$ST"; expect_contains "issue or PR number"
run question close "5/../6" --acted x
expect_status 1 "$ST"; expect_contains "issue or PR number"
run question close 5 "1x" --acted x
expect_status 1 "$ST"; expect_contains "question number"
expect_gh_not_called "issues/5/" "a malformed item reached the API"
fi

if t question_close_refuses_unanswered; then setup_repo; q_reset
export GH_STUB_QROWS='comment\tq\t1\talex\tadded\tA?\ncomment\tother'
run question close 5 --acted "guessed"
expect_status 2 "$ST"
expect_contains "state=QUESTION_UNANSWERED"
expect_gh_not_called "comments -F" "closed a question nobody answered"
run question close 5
expect_status 1 "$ST"; expect_contains "--acted"
fi

# yolo's stop on a question goes through the mechanism, not just prose.
if t question_yolo_puts_its_stop_on_the_record; then
grep -q 'gnadd.sh" question ask' "$ROOT/skills/yolo-gnadd/SKILL.md" && ok \
  || fail "yolo-gnadd does not post its stopping question with question ask"
fi

# ---------------------------------------------------------------- phase

if t phase_status_none; then setup_repo
run phase status
expect_status 0 "$ST"
expect_contains "phase=none"
fi

if t phase_status_open; then setup_repo
export GH_STUB_PHASES='1\tIdea to first version\t3\t2\tfind out whether X'
run phase status
expect_status 0 "$ST"
expect_contains "phase=Idea to first version"
expect_contains "phase_number=1"
expect_contains "open_issues=3"
expect_contains "closed_issues=2"
expect_contains "description=find out whether X"
expect_not_contains "wants exactly one"
fi

if t phase_status_multiple_reports_all; then setup_repo
export GH_STUB_PHASES='1\tPhase A\t1\t0\ta\n2\tPhase B\t0\t0\tb'
run phase status
expect_status 0 "$ST"
expect_contains "phase=Phase A"
expect_contains "phase=Phase B"
expect_contains "wants exactly one"
fi

if t phase_open_creates; then setup_repo
export GH_STUB_API_INPUT="$SANDBOX/api.json"
run phase open "Second phase" --description "try it on a real project; ends when Alex has ruled"
expect_status 0 "$ST"
expect_contains "opened=true"
expect_contains "phase_number=42"
expect_contains "url=https://github.com/stub-owner/stub-repo/milestone/42"
OUT="$(cat "$SANDBOX/api.json")"
expect_contains '"title": "Second phase"'
expect_contains 'ends when Alex has ruled'
expect_not_contains 'due_on'
fi

if t phase_open_refuses_while_one_open; then setup_repo
export GH_STUB_PHASES='1\tIdea to first version\t3\t2\tx'
run phase open "Second phase" --description "y"
expect_status 2 "$ST"
expect_contains "state=PHASE_OPEN"
expect_contains "Idea to first version"
expect_gh_not_called "POST" "created a milestone despite an open phase"
fi

if t phase_open_requires_description; then setup_repo
run phase open "Second phase"
expect_status 1 "$ST"
expect_contains "needs --description"
fi

if t phase_close_with_verdict; then setup_repo
export GH_STUB_PHASES='7\tIdea to first version\t0\t6\tfind out whether X'
export GH_STUB_PHASE_DESC='find out whether X.\nEnds when Alex has ruled.'
export GH_STUB_API_INPUT="$SANDBOX/api.json"
printf 'It works. Rounds felt right, "preview" needs a script.\n' > "$SANDBOX/verdict.txt"
run phase close "Idea to first version" --verdict-file "$SANDBOX/verdict.txt"
expect_status 0 "$ST"
expect_contains "closed=true"
expect_contains "phase_number=7"
expect_gh_called "PATCH repos/{owner}/{repo}/milestones/7" "no PATCH on milestone 7"
OUT="$(cat "$SANDBOX/api.json")"
expect_contains '"state": "closed"'
expect_contains 'find out whether X.\nEnds when Alex has ruled.\n\n## Verdict\n\nIt works. Rounds felt right, \"preview\" needs a script.'
fi

if t phase_close_requires_verdict; then setup_repo
export GH_STUB_PHASES='7\tIdea to first version\t0\t6\tx'
run phase close "Idea to first version"
expect_status 1 "$ST"
expect_contains "needs --verdict"
expect_gh_not_called "PATCH" "closed without a verdict"
fi

if t phase_close_defaults_title_when_one_open; then setup_repo
export GH_STUB_PHASES='7\tIdea to first version\t0\t6\tx'
run phase close --verdict "v"
expect_status 0 "$ST"
expect_contains "phase=Idea to first version"
expect_contains "closed=true"
expect_gh_called "PATCH repos/{owner}/{repo}/milestones/7" "no PATCH on milestone 7"
fi

if t phase_close_needs_title_when_several_open; then setup_repo
export GH_STUB_PHASES='7\tA\t0\t6\tx\n8\tB\t1\t0\ty'
run phase close --verdict "v"
expect_status 1 "$ST"
expect_contains "2 milestones are open"
expect_gh_not_called "PATCH" "closed one of several phases without a title"
fi

if t phase_close_unknown_title; then setup_repo
export GH_STUB_PHASES='7\tIdea to first version\t0\t6\tx'
run phase close "Nope" --verdict "v"
expect_status 2 "$ST"
expect_contains "state=PHASE_NOT_FOUND"
fi

# ---------------------------------------------------------------- init

if t init_turns_on_rails; then setup_repo
export GH_STUB_API_INPUT="$SANDBOX/api.json"
run init
expect_status 0 "$ST"
expect_contains "repo=stub-owner/stub-repo"
expect_contains "merge_policy=squash-only"
expect_contains "ruleset=created"
expect_gh_called "--squash-merge-commit-message pr-title-description" "squash message not set to pr-title-description"
expect_gh_not_called "--squash-merge-commit-title" "uses a flag gh does not have"
OUT="$(cat "$SANDBOX/api.json")"
expect_contains '"name": "gnadd-main"'
expect_contains '"type": "pull_request"'
fi

if t init_rerun_reports_existing_ruleset; then setup_repo
export GH_STUB_RULESETS='gnadd-main'
run init
expect_status 0 "$ST"
expect_contains "ruleset=exists"
expect_gh_not_called "POST" "created a second ruleset"
fi

if t init_ruleset_failure_names_cause; then setup_repo
export GH_STUB_RULESET_FAIL='gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)'
run init
expect_status 0 "$ST"
expect_contains "ruleset=failed"
expect_contains "ruleset_error=gh: Upgrade to GitHub Pro"
fi

if t init_reports_its_uncommitted_files; then setup_repo
run init --ci
expect_status 0 "$ST"
expect_contains "ci=created"
expect_contains "uncommitted=.github/workflows/gnadd-ci.yml"
run conventions --preview "npm run dev"
expect_contains "uncommitted=AGENTS.md,.github/workflows/gnadd-ci.yml"
fi

if t init_reports_none_uncommitted_when_landed; then setup_repo
run init
expect_contains "uncommitted=none"
fi

# ---------------------------------------------------------------- init land

if t init_land_ships_own_files; then setup_repo
export GH_STUB_PR_NUMBER=3
run init --ci
run conventions --preview "npm run dev"
run init land
expect_status 0 "$ST"
expect_contains "branch=quickfix/gnadd-init"
expect_contains "files=AGENTS.md,.github/workflows/gnadd-ci.yml"
expect_contains "pr_number=3"
expect_contains "pr_url=https://github.com/stub-owner/stub-repo/pull/3"
[ "$(git symbolic-ref --short HEAD)" = "quickfix/gnadd-init" ] && ok || fail "not on the landing branch"
[ -z "$(git status --porcelain)" ] && ok || fail "tree not clean after landing"
git ls-files --error-unmatch AGENTS.md .github/workflows/gnadd-ci.yml >/dev/null 2>&1 && ok || fail "init files not committed"
git rev-parse --verify --quiet origin/quickfix/gnadd-init >/dev/null && ok || fail "landing branch not pushed"
expect_gh_called "pr create" "no PR created"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "local main moved"
run state
expect_contains "tree=clean"
run init
expect_contains "uncommitted=none"
fi

if t init_land_nothing_to_land; then setup_repo
run init land
expect_status 0 "$ST"
expect_contains "landed=none"
expect_gh_not_called "pr create" "created a PR with nothing to land"
fi

if t init_land_refuses_foreign_files; then setup_repo
run conventions
echo x > mine.txt
run init land
expect_status 2 "$ST"
expect_contains "state=INIT_LAND_FOREIGN_FILES"
expect_contains "mine.txt"
[ "$(git symbolic-ref --short HEAD)" = "main" ] && ok || fail "left main despite the halt"
fi

if t init_land_refuses_off_main; then setup_repo
git_q checkout -b other
run init land
expect_status 2 "$ST"
expect_contains "state=NOT_ON_MAIN"
fi

if t init_land_refuses_diverged_main; then setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
run conventions
run init land
expect_status 2 "$ST"
expect_contains "state=DIVERGED_MAIN"
fi

# ---------------------------------------------------------------- conventions

if t conventions_creates; then setup_repo
run conventions --preview "npm run dev"
expect_status 0 "$ST"
expect_contains "conventions=created"
expect_contains "preview=npm run dev"
OUT="$(cat AGENTS.md)"
expect_contains "<!-- gnadd:conventions -->"
expect_contains "/prime-gnadd"
expect_contains "Preview launch: npm run dev"
fi

if t conventions_appends_preserving_existing; then setup_repo
printf '# My rules\n\nkeep me\n' > AGENTS.md
run conventions --preview "make run"
expect_status 0 "$ST"
expect_contains "conventions=updated"
OUT="$(cat AGENTS.md)"
expect_contains "keep me"
expect_contains "Preview launch: make run"
case "$OUT" in "# My rules"*) ok ;; *) fail "existing content not preserved at top" ;; esac
fi

if t conventions_rerun_unchanged; then setup_repo
run conventions --preview "npm run dev"
run conventions --preview "npm run dev"
expect_status 0 "$ST"
expect_contains "conventions=unchanged"
[ "$(grep -c 'gnadd:conventions -->' AGENTS.md)" = "2" ] && ok || fail "block duplicated on rerun"
run conventions
expect_contains "conventions=unchanged"
expect_contains "preview=npm run dev"
fi

if t conventions_updates_only_preview; then setup_repo
printf '# My rules\n\nkeep me\n' > AGENTS.md
run conventions --preview "npm run dev"
run conventions --preview "http://localhost:3000"
expect_status 0 "$ST"
expect_contains "conventions=updated"
case "$OUT" in *"conventions=updated"*"note: preview launch line changed"*) ok ;; *) fail "the note came before conventions=updated" ;; esac
OUT="$(cat AGENTS.md)"
expect_contains "keep me"
expect_contains "Preview launch: http://localhost:3000"
expect_not_contains "npm run dev"
[ "$(grep -c '^<!-- gnadd:conventions -->' AGENTS.md)" = "1" ] && ok || fail "block count wrong"
fi

if t conventions_placeholder_without_preview; then setup_repo
run conventions
expect_status 0 "$ST"
expect_contains "conventions=created"
OUT="$(cat AGENTS.md)"
expect_contains "Preview launch: (none yet"
expect_not_contains "Worktree setup:"
fi

if t conventions_writes_setup_line_only_when_given; then setup_repo
run conventions --preview "npm run dev" --setup "./scripts/setup.sh"
expect_status 0 "$ST"
expect_contains "setup=./scripts/setup.sh"
OUT="$(cat AGENTS.md)"
expect_contains "Worktree setup: ./scripts/setup.sh"
run conventions --preview "npm run dev"
expect_contains "conventions=unchanged"
expect_contains "setup=./scripts/setup.sh"
fi

if t conventions_adds_and_updates_setup_line_in_block; then setup_repo
run conventions --preview "npm run dev"
run conventions --setup "make setup"
expect_status 0 "$ST"
expect_contains "conventions=updated"
[ "$(sed -n '/^Worktree setup:/{n;p;}' AGENTS.md)" = "<!-- /gnadd:conventions -->" ] && ok || fail "setup line not inside the block"
run conventions --setup "make setup"
expect_contains "conventions=unchanged"
run conventions --setup "make bootstrap"
expect_contains "conventions=updated"
[ "$(grep -c '^Worktree setup:' AGENTS.md)" = "1" ] && ok || fail "setup line duplicated"
grep -q '^Worktree setup: make bootstrap$' AGENTS.md && ok || fail "setup line not replaced"
fi

if t conventions_setup_none_writes_nothing_and_removes_line; then setup_repo
run conventions --setup none
expect_status 0 "$ST"
grep -q '^Worktree setup:' AGENTS.md && fail "--setup none wrote a line" || ok
run conventions --setup "make setup"
run conventions --setup none
expect_contains "conventions=updated"
expect_not_contains "setup=make setup"
grep -q '^Worktree setup:' AGENTS.md && fail "--setup none left the line" || ok
run conventions --setup none
expect_contains "conventions=unchanged"
fi

if t conventions_setup_without_end_marker_reports_unchanged; then setup_repo
printf '<!-- gnadd:conventions -->\nPreview launch: npm run dev\n' > AGENTS.md
run conventions --setup "make setup"
expect_not_contains "conventions=updated"
expect_contains "conventions=unchanged"
expect_contains "end marker"
grep -q '^Worktree setup:' AGENTS.md && fail "line written outside a closed block" || ok
fi

# conventions and start share one definition of the setup line, so
# conventions updates or removes whatever line start would run.
if t conventions_updates_a_setup_line_written_without_a_space; then setup_repo
run conventions --preview "npm run dev"
sed 's/^<!-- \/gnadd:conventions -->$/Worktree setup:make old\
&/' AGENTS.md > AGENTS.tmp && mv AGENTS.tmp AGENTS.md
run conventions
expect_contains "conventions=unchanged"
expect_contains "setup=make old"
run conventions --setup "make old"
expect_contains "conventions=unchanged"
run conventions --setup "make new"
expect_status 0 "$ST"
expect_contains "conventions=updated"
expect_contains "setup=make new"
[ "$(grep -c '^Worktree setup:' AGENTS.md)" = "1" ] && ok || fail "a second setup line was added"
grep -q '^Worktree setup: make new$' AGENTS.md && ok || fail "the line start would run was not updated"
fi

if t conventions_setup_none_removes_every_line_start_could_run; then setup_repo
run conventions --preview "npm run dev"
printf 'Worktree setup:make one\nWorktree setup:\tmake two\n' >> AGENTS.md
run conventions --setup none
expect_status 0 "$ST"
expect_contains "conventions=updated"
expect_not_contains "setup="
grep -q '^Worktree setup:' AGENTS.md && fail "--setup none left a line start would run" || ok
fi

if t conventions_append_updates_a_handwritten_setup_line; then setup_repo
printf '# My rules\n\nWorktree setup:make old\n' > AGENTS.md
run conventions --preview "npm run dev" --setup "make new"
expect_status 0 "$ST"
expect_contains "conventions=updated"
expect_contains "setup=make new"
[ "$(grep -c '^Worktree setup:' AGENTS.md)" = "1" ] && ok || fail "a second setup line was added"
grep -q '^Worktree setup: make new$' AGENTS.md && ok || fail "the line start would run was not updated"
expect_contains "only the worktree setup line was touched"
expect_contains "worktree setup line changed from 'make old'"
OUT="$(cat AGENTS.md)"
expect_contains "<!-- gnadd:conventions -->"
fi

if t conventions_setup_none_in_any_case; then setup_repo
run conventions --setup None
expect_status 0 "$ST"
grep -q '^Worktree setup:' AGENTS.md && fail "--setup None wrote a line" || ok
run conventions --setup "make setup"
run conventions --setup NONE
expect_contains "conventions=updated"
expect_not_contains "setup="
grep -q '^Worktree setup:' AGENTS.md && fail "--setup NONE left the line" || ok
printf 'Worktree setup: None\n' >> AGENTS.md
run conventions
expect_not_contains "setup="
fi

if t skill_copies_in_sync; then CURRENT=skill_copies_in_sync
for skill in prime-gnadd start-issue-gnadd commit-gnadd resolve-issue-gnadd quickfix-gnadd yolo-gnadd init-gnadd; do
  if [ ! -f "$ROOT/skills/$skill/gnadd.sh" ]; then
    fail "skills/$skill/gnadd.sh missing, run scripts/build.sh"
  elif ! diff -q "$ROOT/bin/gnadd" "$ROOT/skills/$skill/gnadd.sh" >/dev/null; then
    fail "skills/$skill/gnadd.sh out of sync with bin/gnadd, run scripts/build.sh"
  else
    ok
  fi
done
fi

if t plugin_manifests; then CURRENT=plugin_manifests
# The repo root is also a Claude Code plugin: .claude-plugin/plugin.json is the
# plugin and .claude-plugin/marketplace.json is a one-entry marketplace pointing
# at it. Neither may carry a "version" field: with one set, `claude plugin
# update` keeps users on the cached copy until the string changes, which would
# pin the plugin channel to releases while the skills CLI tracks main. Omitted,
# the plugin version is the resolved commit and every merge to main is an
# update, matching the skills CLI (the release baseline stays in bin/gnadd).
# When the claude CLI is on PATH the manifests are validated with it too. The
# only warning the plugin manifest is allowed is the CLAUDE.md-at-root one:
# that file is this repo's own agent instructions and must not ship as plugin
# context, so the warning describes the behavior we want.
for f in plugin.json marketplace.json; do
  if [ ! -f "$ROOT/.claude-plugin/$f" ]; then fail ".claude-plugin/$f missing"
  elif grep -qE '^ *"version" *:' "$ROOT/.claude-plugin/$f"; then
    fail ".claude-plugin/$f sets \"version\", which pins plugin installs to that string instead of tracking main"
  else ok; fi
done
if command -v claude >/dev/null 2>&1; then
  # Two warnings are sanctioned (see above): the CLAUDE.md one and the
  # missing-version one. Anything else the validator reports is a real problem.
  for target in "$ROOT" "$ROOT/.claude-plugin/plugin.json"; do
    OUT="$(claude plugin validate "$target" 2>&1)"; ST=$?
    expect_status 0 "$ST"
    LEFT="$(printf '%s\n' "$OUT" | grep -E '^\s*(❯|-) ' \
      | grep -v 'CLAUDE.md at the plugin root' | grep -v 'No version specified' || true)"
    [ -z "$LEFT" ] && ok || fail "validate $(basename "$target") reported more than the sanctioned warnings: $LEFT"
  done
else
  echo "note: claude CLI not on PATH, plugin manifests checked for version agreement only"
fi
fi

if t skill_self_refs_have_a_copy; then CURRENT=skill_self_refs_have_a_copy
# A SKILL.md that tells the agent to run gnadd.sh from its own directory must
# ship the script there. A skill without a copy (new-issue, vision, help,
# audit) names the sibling that has one: "<prime-gnadd skill-dir>/gnadd.sh".
for dir in "$ROOT"/skills/*/; do
  name="$(basename "$dir")"
  if grep -q '<skill-dir>/gnadd.sh' "$dir/SKILL.md" && [ ! -f "$dir/gnadd.sh" ]; then
    fail "skills/$name/SKILL.md runs <skill-dir>/gnadd.sh but the build does not copy the script there (add it to scripts/build.sh, or name the prime-gnadd copy)"
  else ok; fi
done
fi

if t mechanics_have_no_em_dash; then CURRENT=mechanics_have_no_em_dash
# The changelog and the docs carry no em dashes, so nothing the mechanics
# print or draft may reintroduce one (release.sh's changelog draft did).
EM="$(printf '\xe2\x80\x94')"
for f in "$ROOT"/bin/gnadd "$ROOT"/scripts/*.sh "$ROOT"/test/run.sh; do
  if grep -q "$EM" "$f"; then fail "$(basename "$f") contains an em dash"; else ok; fi
done
fi

if t docs_name_every_skill; then CURRENT=docs_name_every_skill
# The README's skills table is the one list of skills (GNADD.md points at it).
# Every skill on disk must be in it, and no doc may name a skill that is not on disk.
for dir in "$ROOT"/skills/*/; do
  name="$(basename "$dir")"
  if grep -q "^| \`$name\`" "$ROOT/README.md"; then ok
  else fail "skills/$name is missing from the README skills table"; fi
done
for doc in README.md GNADD.md; do
  for name in $(grep -oE '[a-z]+(-[a-z]+)*-gnadd' "$ROOT/$doc" | sort -u); do
    if [ -d "$ROOT/skills/$name" ]; then ok
    else fail "$doc names '$name' but skills/$name does not exist"; fi
  done
done
fi

# ---------------------------------------------------------------- runner
#
# Issue #122: the suite runs one case by name or by glob. Each check runs a
# copy of this suite under the same bash with a filter that cannot select a
# runner case, so nothing recurses.

if t runner_name_runs_that_case_alone; then
OUT="$("$BASH" "$ROOT/test/run.sh" state_synced 2>&1)"; ST=$?
expect_status 0 "$ST"
expect_contains "ran 1 of "
expect_not_contains "lint"
fi

if t runner_glob_runs_every_match; then
OUT="$("$BASH" "$ROOT/test/run.sh" 'state_diverged*' 2>&1)"; ST=$?
expect_status 0 "$ST"
expect_contains "ran 2 of "
fi

if t runner_no_match_fails; then
OUT="$("$BASH" "$ROOT/test/run.sh" no_case_has_this_name 2>&1)"; ST=$?
expect_status 2 "$ST"
expect_contains "no case matches 'no_case_has_this_name'"
expect_not_contains "passed:"
fi

if t runner_selected_failure_still_fails; then
# A copy of the suite with one failing case: selected by name, it fails.
RCOPY="$(mktemp -d)"
cp -R "$ROOT/bin" "$ROOT/test" "$RCOPY/"
sed 's/^if t state_synced; then setup_repo$/if t state_synced; then setup_repo; fail "planted"/' \
  "$ROOT/test/run.sh" > "$RCOPY/test/run.sh"
OUT="$("$BASH" "$RCOPY/test/run.sh" state_synced 2>&1)"; ST=$?
expect_status 1 "$ST"
expect_contains "FAIL state_synced: planted"
rm -rf "$RCOPY"
fi

# ---------------------------------------------------------------- lint

if t lint; then
# scripts/lint.sh is the one lint definition, shared with CI. Without
# shellcheck nothing is linted, and the run says so instead of passing.
OUT="$("$BASH" "$ROOT/scripts/lint.sh" 2>&1)"; ST=$?
case "$ST" in
  0) ok ;;
  77) LINT_SKIPPED=1; printf 'SKIPPED %s: shellcheck not installed, nothing was linted (CI lints)\n' "$CURRENT" ;;
  *) fail "scripts/lint.sh exited $ST: $OUT" ;;
esac
fi

# ---------------------------------------------------------------- summary

if [ "$RAN" -eq 0 ]; then
  echo "no case matches '$FILTER', so nothing ran. This is not a pass." >&2
  exit 2
fi
echo
echo "ran $RAN of $CASES cases  checks passed: $PASS  failed: $FAIL"
if [ "${LINT_SKIPPED:-0}" = 1 ]; then
  echo "lint SKIPPED: shellcheck is not installed, so this run did not check what CI checks"
fi
if [ $((PASS+FAIL)) -eq 0 ]; then
  echo "no check ran, so this is not a pass." >&2
  exit 2
fi
if [ "$FAIL" -gt 0 ]; then
  printf '  %s\n' "${FAILURES[@]}"
  exit 1
fi
