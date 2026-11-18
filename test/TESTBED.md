# The testbed: exercising the whole loop on a throwaway repo

A procedure for an agent to test GNADD end to end after a change to the skills or the script. It describes how the run goes. It tracks nothing: results go to GitHub issues on this repo, never to a file here. Last run: 2026-09-06 on `AlexHagemeister/gnadd-testbed-tickr`, findings filed as issues #94 to #102. The worktree and question phases were added after that run and have not yet been run on live GitHub.

## Setup

1. Seed a tiny app with a real preview line (a static page served by `python3 -m http.server` is enough) and a `test/run.sh` smoke test. Push it to a fresh GitHub repo. A public repo exercises the `main` ruleset; a private one on a free plan gets a 403 there and tests only the client-side rails.
2. Refresh the installed skills first (`scripts/sync.sh` for a local checkout) so the run exercises the change, not the last release.
3. Run each phase as its own subagent, in sequence, with a shared brief. A phase agent plays both the agent and the user: it follows each SKILL.md literally, answers every gate in character as a terse solo developer, and logs every simulated exchange verbatim, marked as simulated. It never skips a gate because it is also the user, never works around a `state=` halt, and appends findings to a file as it goes so nothing is lost to context.

## Phases

- init, vision (land VISION.md by the route vision names), three new-issue runs, prime.
- start-issue on one issue with at least two build/try/feedback rounds, commit with round comments, resolve through merge and cleanup.
- yolo on one issue with a real fresh-context review subagent, one quickfix, a deliberate stray commit on main rescued through `doctor --rescue-main <name>` and landed through an issue with `start <N> <slug> --from <name>`.
- A cold resume: one agent stops mid-issue after a checkpoint, a second agent with no memory of it resumes from the branch and the GitHub record alone, then resolve, phase close, audit.
- Parallel worktrees. Land a `Worktree setup:` line on main first (`conventions --setup <cmd>`, shipped as a quickfix), because `start` reads it from the branch it checks out. Make two linked folders with `git worktree add --detach <path> origin/main` (gnadd creates none) and run start-issue on a different issue in each. Each first `start` prints `setup_command=` and `setup=ran`, and the primary checkout is never set up. `state` from the primary checkout lists `worktrees=` and one `in_flight=` line per branch with its folder. Starting one folder's issue from the other folder halts `state=BRANCH_IN_WORKTREE`. One setup fails on purpose (a command that needs a file the fresh folder lacks): `start` halts `state=SETUP_FAILED`, and the same `start` rerun after the fix retries the setup. Resolve both issues through merge: each folder parks on `origin/main`, and `state` from the primary checkout lists the parked folders as `idle_folder=`.
- Questions on the record. `question ask --to <login> --on <N> --question <q> --options <o> --recommend <r>` on an open issue, and one with `--title <t>` in place of `--on` (a new issue labeled `question`, so the repo needs that label). Asking `--on` a closed item halts `state=ITEM_CLOSED`. prime shows both as unanswered. `question close <N> --acted <text>` before any answer halts `state=QUESTION_UNANSWERED`. Answer one with a plain reply in its thread and the other in chat, recorded with `question answer <N> --answer <text>`. `question list` then reports both as answered. Close both: the question issue closes with its last question, and each assignment comes off only if asking added it.

## What each phase reports

Per skill, in order: what ran and the key output verbatim, bugs (with reproduction), friction (ambiguity, a lookup the skill could have done itself, a reference to something that does not exist), notes (praise is data too), and a rough tool-call count. The parent verifies any script bug against `bin/gnadd` before filing, and files bugs and enhancements as separate issues with a batch issue for small text frictions.
