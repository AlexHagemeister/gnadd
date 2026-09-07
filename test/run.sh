#!/usr/bin/env bash
# Test suite for bin/gnadd. Zero dependencies beyond bash + git: gh is
# stubbed (test/stub/gh), remotes are local bare repos.
#
# Every incident that shaped a GNADD design decision (GNADD.md Part 5) has a
# regression test here. If you change bin/gnadd, this suite is what tells
# you whether the guarantees still hold.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GNADD="$ROOT/bin/gnadd"
STUB="$ROOT/test/stub/gh"

PASS=0
FAIL=0
CURRENT=""
FAILURES=()

# ---------------------------------------------------------------- helpers

fail() {
  FAIL=$((FAIL+1))
  FAILURES+=("$CURRENT: $*")
  printf 'FAIL %s: %s\n' "$CURRENT" "$*"
}

ok() { PASS=$((PASS+1)); }

expect_status() { # expect_status <want> <got>
  [ "$2" = "$1" ] && ok || fail "expected exit $1, got $2 — output: $OUT"
}

expect_contains() { # expect_contains <needle>
  case "$OUT" in
    *"$1"*) ok ;;
    *) fail "output missing '$1' — output: $OUT" ;;
  esac
}

expect_not_contains() {
  case "$OUT" in
    *"$1"*) fail "output unexpectedly contains '$1' — output: $OUT" ;;
    *) ok ;;
  esac
}

run() { # run <args...> — capture OUT and ST
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
  unset GH_STUB_PR_STATE GH_STUB_PR_NUMBER GH_STUB_PR_URL \
        GH_STUB_MERGEABLE GH_STUB_MERGED_AT GH_STUB_MERGE_COMMIT \
        GH_STUB_CHECKS GH_STUB_FAIL GH_STUB_ROUND_COUNT \
        GH_STUB_ROUND_BODIES GH_STUB_COMMENT_FILE GH_STUB_PHASES \
        GH_STUB_PHASE_DESC GH_STUB_API_INPUT GH_STUB_RULESETS 2>/dev/null || true
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

t() { CURRENT="$1"; }

# ---------------------------------------------------------------- state

t state_synced; setup_repo
run state
expect_status 0 "$ST"
expect_contains "main_state=synced"
expect_contains "tree=clean"
expect_contains "branch=main"

t state_behind; setup_repo
advance_origin_main
run state
expect_status 0 "$ST"
expect_contains "main_state=behind"
expect_contains "main_behind=1"

t state_diverged; setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray commit on main"
run state
expect_status 0 "$ST"
expect_contains "main_state=diverged"
expect_contains "main_ahead=1"
expect_contains "stray commit on main"

t state_reports_stash; setup_repo
echo x > s.txt && git_q add s.txt && git stash >/dev/null 2>&1
run state
expect_contains "stashes=1"

# ---------------------------------------------------------------- start

t start_fresh; setup_repo
run start 5 fix-thing
expect_status 0 "$ST"
expect_contains "result=created"
expect_contains "branch=issue-5/fix-thing"
[ "$(git symbolic-ref --short HEAD)" = "issue-5/fix-thing" ] && ok || fail "not on new branch"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main moved"

t start_syncs_behind_main; setup_repo
advance_origin_main
run start 6 sync-me
expect_status 0 "$ST"
expect_contains "result=created"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main not fast-forwarded"

t start_halts_on_diverged_main; setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
run start 7 nope
expect_status 2 "$ST"
expect_contains "state=DIVERGED_MAIN"
git show-ref --verify --quiet refs/heads/issue-7/nope && fail "branch was created despite halt" || ok

t start_halts_on_dirty_tree; setup_repo
echo x > dirty.txt
run start 8 nope
expect_status 2 "$ST"
expect_contains "state=DIRTY_TREE"
git show-ref --verify --quiet refs/heads/issue-8/nope && fail "branch was created despite halt" || ok

t start_carry; setup_repo
echo x > dirty.txt
run start 9 rescue --carry
expect_status 0 "$ST"
expect_contains "result=created-carry"
[ "$(git symbolic-ref --short HEAD)" = "issue-9/rescue" ] && ok || fail "not on carry branch"
[ -f dirty.txt ] && ok || fail "dirty file lost in carry"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main gained a commit"

t start_carry_refuses_off_main; setup_repo
git_q checkout -b issue-1/elsewhere
echo x > dirty.txt
run start 9 rescue --carry
expect_status 2 "$ST"
expect_contains "state=NOT_ON_MAIN"

t start_resume_pulls_remote; setup_repo
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

t start_resume_halts_on_diverged_branch; setup_repo
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

# ---------------------------------------------------------------- guard-commit

t guard_commit_on_main; setup_repo
run guard-commit
expect_status 2 "$ST"
expect_contains "state=ON_MAIN"

t guard_commit_on_issue_branch; setup_repo
git_q checkout -b issue-3/ok
run guard-commit
expect_status 0 "$ST"
expect_contains "issue=3"

t guard_commit_detached; setup_repo
git_q checkout --detach HEAD
run guard-commit
expect_status 2 "$ST"
expect_contains "state=DETACHED_HEAD"

# ---------------------------------------------------------------- ship

t ship_push_happy; setup_repo
run start 12 shippable
echo work > w.txt && git_q add w.txt && git_q commit -m "work"
run ship push
expect_status 0 "$ST"
expect_contains "pushed=true"
expect_contains "pr_exists=false"
git ls-remote --exit-code --heads origin issue-12/shippable >/dev/null 2>&1 && ok || fail "branch not on remote"

t ship_push_nothing_to_ship; setup_repo
run start 13 empty
run ship push
expect_status 2 "$ST"
expect_contains "state=NOTHING_TO_SHIP"

t ship_push_refuses_main; setup_repo
run ship push
expect_status 2 "$ST"
expect_contains "state=ON_MAIN"

t ship_push_refuses_random_branch; setup_repo
git_q checkout -b experiment
echo x > x.txt && git_q add x.txt && git_q commit -m x
run ship push
expect_status 2 "$ST"
expect_contains "state=NOT_ISSUE_BRANCH"
run ship push --any-branch
expect_status 0 "$ST"

t ship_push_detects_existing_pr; setup_repo
run start 14 has-pr
echo work > w.txt && git_q add w.txt && git_q commit -m "work"
export GH_STUB_PR_STATE=OPEN GH_STUB_PR_NUMBER=44 GH_STUB_PR_URL=https://x/pull/44
run ship push
expect_status 0 "$ST"
expect_contains "pr_exists=true"
expect_contains "pr_number=44"

t ship_merge_conflicting_never_merges; setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=CONFLICTING
run ship merge 44
expect_status 2 "$ST"
expect_contains "state=PR_CONFLICTING"
grep -q "pr merge" "$GH_STUB_LOG" && fail "gh pr merge was called on a conflicting PR" || ok

t ship_merge_ok; setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
run ship merge 44
expect_status 0 "$ST"
expect_contains "merged=true"
grep -q "pr merge 44 --squash" "$GH_STUB_LOG" && ok || fail "gh pr merge --squash not called"

t ship_merge_unknown_mergeability; setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=UNKNOWN
run ship merge 44
expect_status 2 "$ST"
expect_contains "state=MERGEABILITY_UNKNOWN"

# ---------------------------------------------------------------- sync-main / cleanup

t sync_main_fast_forwards; setup_repo
git_q checkout -b issue-15/done
advance_origin_main
run sync-main
expect_status 0 "$ST"
expect_contains "synced=true"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main not synced"

t sync_main_halts_on_divergence; setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
git_q checkout -b issue-16/done
run sync-main
expect_status 2 "$ST"
expect_contains "state=DIVERGED_MAIN"

t cleanup_refuses_unmerged; setup_repo
git_q branch issue-17/keep
export GH_STUB_PR_STATE=OPEN
run cleanup 45 issue-17/keep
expect_status 2 "$ST"
expect_contains "state=NOT_MERGED"
git show-ref --verify --quiet refs/heads/issue-17/keep && ok || fail "branch deleted despite unmerged PR"

t cleanup_after_merge; setup_repo
git_q checkout -b issue-18/gone
echo x > x.txt && git_q add x.txt && git_q commit -m x
git_q push -u origin HEAD
git_q checkout main
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-07-17T00:00:00Z GH_STUB_MERGE_COMMIT=deadbeef
run cleanup 46 issue-18/gone
expect_status 0 "$ST"
expect_contains "local_deleted=true"
expect_contains "remote_deleted=true"
expect_contains "merge_commit=deadbeef"
git show-ref --verify --quiet refs/heads/issue-18/gone && fail "local branch survived" || ok
git ls-remote --exit-code --heads origin issue-18/gone >/dev/null 2>&1 && fail "remote branch survived" || ok

t cleanup_refuses_from_target_branch; setup_repo
git_q checkout -b issue-19/here
export GH_STUB_PR_STATE=MERGED GH_STUB_MERGED_AT=2026-07-17T00:00:00Z
run cleanup 47 issue-19/here
expect_status 2 "$ST"
expect_contains "state=ON_TARGET_BRANCH"

# ---------------------------------------------------------------- doctor

t doctor_clean; setup_repo
run doctor
expect_status 0 "$ST"
expect_contains "findings=0"

t doctor_finds_bad_states; setup_repo
echo x > s.txt && git_q add s.txt && git stash >/dev/null 2>&1
echo y > local.txt && git_q add local.txt && git_q commit -m "stray"
run doctor
expect_status 0 "$ST"
expect_contains "finding=DIVERGED_MAIN"
expect_contains "finding=STASHES"

t doctor_rescue_main; setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray commit"
STRAY="$(git rev-parse HEAD)"
run doctor --rescue-main rescue/stray
expect_status 0 "$ST"
expect_contains "rescued=true"
[ "$(git rev-parse rescue/stray)" = "$STRAY" ] && ok || fail "rescue branch lost the stray commit"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main not realigned"
[ "$(git symbolic-ref --short HEAD)" = "rescue/stray" ] && ok || fail "not standing on rescue branch"

t doctor_rescue_refuses_when_not_diverged; setup_repo
run doctor --rescue-main rescue/nothing
expect_status 2 "$ST"
expect_contains "state=NOT_DIVERGED"

# ---------------------------------------------------------------- test / misc

t test_detects_makefile; setup_repo
printf 'test:\n\t@echo make-tests-ran\n' > Makefile
run test
expect_status 0 "$ST"
expect_contains "runner=make"
expect_contains "make-tests-ran"

t test_no_tests; setup_repo
run test
expect_status 0 "$ST"
expect_contains "state=NO_TESTS"

t release_drafts_notes_when_entry_missing
# The changelog gate must draft grouped notes from merged-PR history when the
# entry is missing, and still block the release. Runs against the real repo
# read-only: the gate exits before any stamping for a version with no entry.
TREE_BEFORE="$(git -C "$ROOT" status --porcelain)"
OUT="$(bash "$ROOT/scripts/release.sh" v9.9.9 2>&1)"; ST=$?
TREE_AFTER="$(git -C "$ROOT" status --porcelain)"
expect_status 1 "$ST"
expect_contains 'no "## [9.9.9]" entry'
expect_contains "## [9.9.9]"
# Bullets only exist when the range has commits — at a freshly tagged HEAD
# the range is empty and a header-only draft is correct.
REL_LAST_TAG="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
REL_COUNT="$(git -C "$ROOT" rev-list --count "${REL_LAST_TAG:+$REL_LAST_TAG..}HEAD" 2>/dev/null || echo 0)"
if [ "$REL_COUNT" -gt 0 ]; then expect_contains "- "; else ok; fi
[ "$TREE_BEFORE" = "$TREE_AFTER" ] && ok || fail "drafting modified the repo working tree"

t version_reports_channel_baseline; setup_repo
run version
expect_status 0 "$ST"
expect_contains "gnadd 0."
expect_contains "channel=main"
expect_contains "release baseline"

# ---------------------------------------------------------------- quickfix

t quickfix_start_creates_branch; setup_repo
run quickfix start fix-typo
expect_status 0 "$ST"
expect_contains "result=created"
expect_contains "branch=quickfix/fix-typo"

t quickfix_start_carries_dirty_main; setup_repo
echo tweak >> README.md
run quickfix start doc-tweak --carry
expect_status 0 "$ST"
expect_contains "result=created-carry"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main was modified by carry"

t quickfix_start_refuses_existing_branch; setup_repo
git_q branch quickfix/dup
run quickfix start dup
expect_status 2 "$ST"
expect_contains "state=QF_BRANCH_EXISTS"

t quickfix_start_halts_on_diverged_main; setup_repo
echo x > local.txt && git_q add local.txt && git_q commit -m "stray"
run quickfix start anything
expect_status 2 "$ST"
expect_contains "state=DIVERGED_MAIN"

t quickfix_guard_small_change_ok; setup_repo
run quickfix start small
echo tweak >> README.md && git_q add README.md && git_q commit -m "tweak"
run quickfix guard
expect_status 0 "$ST"
expect_contains "guard=ok"
expect_contains "files=1"

t quickfix_guard_refuses_too_many_lines; setup_repo
run quickfix start big
seq 1 40 > big.txt && git_q add big.txt && git_q commit -m "big"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=TOO_BIG"

t quickfix_guard_refuses_too_many_files; setup_repo
run quickfix start wide
for f in a b c d; do echo x > "$f.txt"; done
git_q add . && git_q commit -m "wide"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=TOO_BIG"

t quickfix_guard_refuses_protected_paths; setup_repo
run quickfix start sneaky
mkdir -p scripts && echo x > scripts/hack.sh
git_q add . && git_q commit -m "sneaky"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=PROTECTED_PATH"

t quickfix_guard_refuses_gnadd_copies; setup_repo
run quickfix start copy-edit
mkdir -p skills/foo && echo x > skills/foo/gnadd.sh
git_q add . && git_q commit -m "copy edit"
run quickfix guard
expect_status 2 "$ST"
expect_contains "state=PROTECTED_PATH"

t quickfix_ship_happy; setup_repo
run quickfix start shippable
echo tweak >> README.md && git_q add README.md && git_q commit -m "tweak"
run quickfix ship
expect_status 0 "$ST"
expect_contains "guard=ok"
expect_contains "pushed=true"
[ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ] && ok || fail "main gained a commit"

t quickfix_ship_refuses_non_quickfix_branch; setup_repo
git_q checkout -b issue-20/not-quickfix
run quickfix ship
expect_status 2 "$ST"
expect_contains "state=NOT_QUICKFIX_BRANCH"

t quickfix_merge_waits_for_ci; setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='test\tpending\t0\turl'
run quickfix merge 50
expect_status 2 "$ST"
expect_contains "state=QF_CHECKS_PENDING"
grep -q "pr merge" "$GH_STUB_LOG" && fail "merged with CI still pending" || ok

t quickfix_merge_refuses_failed_ci; setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='test\tfail\t5s\turl'
run quickfix merge 50
expect_status 2 "$ST"
expect_contains "state=QF_CHECK_FAILED"
grep -q "pr merge" "$GH_STUB_LOG" && fail "merged despite failing CI" || ok

t quickfix_merge_after_green_ci; setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='CodeRabbit\tfail\t0\turl\ntest\tpass\t5s\turl'
run quickfix merge 50
expect_status 0 "$ST"
expect_contains "check_status=pass"
expect_contains "merged=true"
grep -q "pr merge 50 --squash" "$GH_STUB_LOG" && ok || fail "gh pr merge --squash not called"

t quickfix_merge_refuses_when_no_checks; setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
run quickfix merge 50
expect_status 2 "$ST"
expect_contains "state=QF_NO_CHECKS"
run quickfix merge 50 --no-check
expect_status 0 "$ST"
expect_contains "merged=true"

t quickfix_merge_unknown_check_name; setup_repo
export GH_STUB_PR_STATE=OPEN GH_STUB_MERGEABLE=MERGEABLE
export GH_STUB_CHECKS='ci-build\tpass\t5s\turl'
run quickfix merge 50
expect_status 2 "$ST"
expect_contains "state=QF_CHECK_NOT_FOUND"
run quickfix merge 50 --check ci-build
expect_status 0 "$ST"
expect_contains "merged=true"

# ---------------------------------------------------------------- trace

t trace_records_each_invocation; setup_repo
run state
run guard-commit
run trace show
expect_status 0 "$ST"
expect_contains "gnadd state status=0"
expect_contains "gnadd guard-commit status=2"

t trace_reset_and_meta_commands_leave_no_lines; setup_repo
run state
run trace reset
run version
run trace show
expect_status 0 "$ST"
expect_contains "trace=empty"

t trace_survives_midpipe_kill; setup_repo
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

t trace_stays_out_of_working_tree; setup_repo
run state
[ -z "$(git status --porcelain)" ] && ok || fail "trace log dirtied the working tree"
[ -f .git/gnadd-trace.log ] && ok || fail "trace log not written to .git/"

# ---------------------------------------------------------------- round

t round_post_first_round; setup_repo
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
grep -q "gh issue comment 5 --body-file" "$GH_STUB_LOG" && ok || fail "comment not posted via gh issue comment"

t round_post_numbers_from_record; setup_repo
run start 6 rounds
export GH_STUB_ROUND_COUNT=2 GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round post --changed "third slice" --feedback "ok"
expect_status 0 "$ST"
expect_contains "round=3"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "## Round 3"

t round_post_feedback_file_verbatim; setup_repo
run start 7 rounds
export GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
printf 'teh spacing is off\nand also the font\n' > "$SANDBOX/fb.txt"
run round post --changed "spacing" --feedback-file "$SANDBOX/fb.txt"
expect_status 0 "$ST"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "> teh spacing is off"
expect_contains "> and also the font"

t round_post_no_feedback_is_explicit; setup_repo
run start 8 rounds
export GH_STUB_COMMENT_FILE="$SANDBOX/comment.md"
run round post --changed "scaffold" --no-feedback "first slice, nothing to try yet"
expect_status 0 "$ST"
OUT="$(cat "$SANDBOX/comment.md")"
expect_contains "**Feedback:** none this round (first slice, nothing to try yet)."
expect_not_contains "transcribed"

t round_post_refuses_empty_feedback; setup_repo
run start 9 rounds
run round post --changed "x"
expect_status 1 "$ST"
expect_contains "never inferred"
run round post --changed "x" --feedback ""
expect_status 1 "$ST"
expect_contains "feedback text is empty"
run round post --changed "x" --feedback "a" --no-feedback "b"
expect_status 1 "$ST"
grep -q "issue comment" "$GH_STUB_LOG" && fail "posted despite refusal" || ok

t round_post_refuses_non_issue_branch; setup_repo
run round post --changed "x" --feedback "y"
expect_status 2 "$ST"
expect_contains "state=NOT_ISSUE_BRANCH"
git_q checkout -b quickfix/typo
run round post --changed "x" --feedback "y"
expect_status 2 "$ST"
expect_contains "state=NOT_ISSUE_BRANCH"
grep -q "issue comment" "$GH_STUB_LOG" && fail "posted off an issue branch" || ok

t round_list_in_order; setup_repo
run start 10 rounds
export GH_STUB_ROUND_COUNT=2
export GH_STUB_ROUND_BODIES='<!-- gnadd:round -->\n## Round 1\n\n**Changed:** a\n<!-- gnadd:round -->\n## Round 2\n\n**Changed:** b'
run round list
expect_status 0 "$ST"
expect_contains "issue=10"
expect_contains "rounds=2"
expect_not_contains "gnadd:round"
case "$OUT" in *"Round 1"*"Round 2"*) ok ;; *) fail "rounds out of order: $OUT" ;; esac

t round_list_none; setup_repo
run round list 11
expect_status 0 "$ST"
expect_contains "rounds=0"

# ---------------------------------------------------------------- phase

t phase_status_none; setup_repo
run phase status
expect_status 0 "$ST"
expect_contains "phase=none"

t phase_status_open; setup_repo
export GH_STUB_PHASES='1\tIdea to first version\t3\t2\tfind out whether X'
run phase status
expect_status 0 "$ST"
expect_contains "phase=Idea to first version"
expect_contains "phase_number=1"
expect_contains "open_issues=3"
expect_contains "closed_issues=2"
expect_contains "description=find out whether X"
expect_not_contains "wants exactly one"

t phase_status_multiple_reports_all; setup_repo
export GH_STUB_PHASES='1\tPhase A\t1\t0\ta\n2\tPhase B\t0\t0\tb'
run phase status
expect_status 0 "$ST"
expect_contains "phase=Phase A"
expect_contains "phase=Phase B"
expect_contains "wants exactly one"

t phase_open_creates; setup_repo
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

t phase_open_refuses_while_one_open; setup_repo
export GH_STUB_PHASES='1\tIdea to first version\t3\t2\tx'
run phase open "Second phase" --description "y"
expect_status 2 "$ST"
expect_contains "state=PHASE_OPEN"
expect_contains "Idea to first version"
grep -q "POST" "$GH_STUB_LOG" && fail "created a milestone despite an open phase" || ok

t phase_open_requires_description; setup_repo
run phase open "Second phase"
expect_status 1 "$ST"
expect_contains "needs --description"

t phase_close_with_verdict; setup_repo
export GH_STUB_PHASES='7\tIdea to first version\t0\t6\tfind out whether X'
export GH_STUB_PHASE_DESC='find out whether X.\nEnds when Alex has ruled.'
export GH_STUB_API_INPUT="$SANDBOX/api.json"
printf 'It works. Rounds felt right, "preview" needs a script.\n' > "$SANDBOX/verdict.txt"
run phase close "Idea to first version" --verdict-file "$SANDBOX/verdict.txt"
expect_status 0 "$ST"
expect_contains "closed=true"
expect_contains "phase_number=7"
grep -q "PATCH repos/{owner}/{repo}/milestones/7" "$GH_STUB_LOG" && ok || fail "no PATCH on milestone 7"
OUT="$(cat "$SANDBOX/api.json")"
expect_contains '"state": "closed"'
expect_contains 'find out whether X.\nEnds when Alex has ruled.\n\n## Verdict\n\nIt works. Rounds felt right, \"preview\" needs a script.'

t phase_close_requires_verdict; setup_repo
export GH_STUB_PHASES='7\tIdea to first version\t0\t6\tx'
run phase close "Idea to first version"
expect_status 1 "$ST"
expect_contains "needs --verdict"
grep -q "PATCH" "$GH_STUB_LOG" && fail "closed without a verdict" || ok

t phase_close_unknown_title; setup_repo
export GH_STUB_PHASES='7\tIdea to first version\t0\t6\tx'
run phase close "Nope" --verdict "v"
expect_status 2 "$ST"
expect_contains "state=PHASE_NOT_FOUND"

# ---------------------------------------------------------------- init

t init_turns_on_rails; setup_repo
export GH_STUB_API_INPUT="$SANDBOX/api.json"
run init
expect_status 0 "$ST"
expect_contains "repo=stub-owner/stub-repo"
expect_contains "merge_policy=squash-only"
expect_contains "ruleset=created"
grep -q -- "--squash-merge-commit-message pr-title-description" "$GH_STUB_LOG" && ok || fail "squash message not set to pr-title-description"
grep -q -- "--squash-merge-commit-title" "$GH_STUB_LOG" && fail "uses a flag gh does not have" || ok
OUT="$(cat "$SANDBOX/api.json")"
expect_contains '"name": "gnadd-main"'
expect_contains '"type": "pull_request"'

t init_rerun_reports_existing_ruleset; setup_repo
export GH_STUB_RULESETS='gnadd-main'
run init
expect_status 0 "$ST"
expect_contains "ruleset=exists"
grep -q "POST" "$GH_STUB_LOG" && fail "created a second ruleset" || ok

# ---------------------------------------------------------------- conventions

t conventions_creates; setup_repo
run conventions --preview "npm run dev"
expect_status 0 "$ST"
expect_contains "conventions=created"
expect_contains "preview=npm run dev"
OUT="$(cat AGENTS.md)"
expect_contains "<!-- gnadd:conventions -->"
expect_contains "/prime-gnadd"
expect_contains "Preview launch: npm run dev"

t conventions_appends_preserving_existing; setup_repo
printf '# My rules\n\nkeep me\n' > AGENTS.md
run conventions --preview "make run"
expect_status 0 "$ST"
expect_contains "conventions=updated"
OUT="$(cat AGENTS.md)"
expect_contains "keep me"
expect_contains "Preview launch: make run"
case "$OUT" in "# My rules"*) ok ;; *) fail "existing content not preserved at top" ;; esac

t conventions_rerun_unchanged; setup_repo
run conventions --preview "npm run dev"
run conventions --preview "npm run dev"
expect_status 0 "$ST"
expect_contains "conventions=unchanged"
[ "$(grep -c 'gnadd:conventions -->' AGENTS.md)" = "2" ] && ok || fail "block duplicated on rerun"
run conventions
expect_contains "conventions=unchanged"
expect_contains "preview=npm run dev"

t conventions_updates_only_preview; setup_repo
printf '# My rules\n\nkeep me\n' > AGENTS.md
run conventions --preview "npm run dev"
run conventions --preview "http://localhost:3000"
expect_status 0 "$ST"
expect_contains "conventions=updated"
OUT="$(cat AGENTS.md)"
expect_contains "keep me"
expect_contains "Preview launch: http://localhost:3000"
expect_not_contains "npm run dev"
[ "$(grep -c '^<!-- gnadd:conventions -->' AGENTS.md)" = "1" ] && ok || fail "block count wrong"

t conventions_placeholder_without_preview; setup_repo
run conventions
expect_status 0 "$ST"
expect_contains "conventions=created"
OUT="$(cat AGENTS.md)"
expect_contains "Preview launch: (none yet"

t skill_copies_in_sync; CURRENT=skill_copies_in_sync
for skill in prime-gnadd start-issue-gnadd commit-gnadd resolve-issue-gnadd quickfix-gnadd yolo-gnadd init-gnadd; do
  if [ ! -f "$ROOT/skills/$skill/gnadd.sh" ]; then
    fail "skills/$skill/gnadd.sh missing — run scripts/build.sh"
  elif ! diff -q "$ROOT/bin/gnadd" "$ROOT/skills/$skill/gnadd.sh" >/dev/null; then
    fail "skills/$skill/gnadd.sh out of sync with bin/gnadd — run scripts/build.sh"
  else
    ok
  fi
done

t plugin_manifests; CURRENT=plugin_manifests
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

t skill_self_refs_have_a_copy; CURRENT=skill_self_refs_have_a_copy
# A SKILL.md that tells the agent to run gnadd.sh from its own directory must
# ship the script there. A skill without a copy (new-issue, vision, help,
# audit) names the sibling that has one: "<prime-gnadd skill-dir>/gnadd.sh".
for dir in "$ROOT"/skills/*/; do
  name="$(basename "$dir")"
  if grep -q '<skill-dir>/gnadd.sh' "$dir/SKILL.md" && [ ! -f "$dir/gnadd.sh" ]; then
    fail "skills/$name/SKILL.md runs <skill-dir>/gnadd.sh but the build does not copy the script there (add it to scripts/build.sh, or name the prime-gnadd copy)"
  else ok; fi
done

t docs_name_every_skill; CURRENT=docs_name_every_skill
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

# ---------------------------------------------------------------- summary

echo
echo "passed: $PASS  failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf '  %s\n' "${FAILURES[@]}"
  exit 1
fi
