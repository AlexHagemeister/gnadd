# GNADD — Git-Native Agent-Driven Development

A lightweight project-management workflow where GitHub Issues, branches, PRs, and
git history are the **sole** system of record. No external trackers, no markdown
task files. Issues capture intent (behavioral specs), PRs capture outcome, and a
coding agent handles the git mechanics through a set of skills.

This document is the canonical description of the workflow. Parts 1–3 are the
user's guide — start there, and come back for refreshers. Part 4 is the reference
model. Part 5 records the design decisions and their rationale. The skills are the
executable spec — when this doc and a skill disagree on a mechanical detail, **the
skill wins** and this doc should be corrected.

---

## How this doc relates to the skills

| Layer | Lives at | Authoritative for | Edited by |
|---|---|---|---|
| **Script** | `bin/gnadd` (canonical); bundled into skills as `gnadd.sh` by `scripts/build.sh` | The git mechanics themselves — every sequence, guard, and halt, enforced in code | Claude; verified by `test/run.sh` |
| **Skills** | `skills/<name>/SKILL.md` in this repo | Judgment and conversation: the gates, questions, and interpretation around the script | Claude |
| **Skills (installed)** | Agent skills dir via `npx skills add` | Runtime copy your agent loads (script travels inside each skill) | Install once; refresh per install path — GitHub installs: `npx skills update` in the matching scope; local-checkout installs: `scripts/sync.sh` (see help-gnadd's Install & Update) |
| **This doc** | `GNADD.md` in this repo | The model, the rationale, and how to drive it | Claude |
| **Instructions** | Claude Desktop settings (a pointer to this doc) | Telling Claude this doc exists | You (once) |

The script carries the mechanics; the skills carry the judgment around them. This
doc deliberately does **not** restate either — that would create copies that drift
apart. It concentrates on the things code can't hold: the model, the human's role,
and the reasoning behind the design. When this doc and a skill disagree on a
mechanical detail, the skill wins; when a skill and the script disagree, the
script wins — it is the layer with tests.

---

## The model in three sentences

GitHub is the entire project-management system: **issues** say what to build,
**branches** are where work happens, **PRs** record what shipped. You don't need
to know git — five skills run every git operation and stop to ask you
whenever a decision matters. Your job is to describe work well, answer the skills'
questions deliberately, and read diffs before merging.

**Prerequisites:** A coding agent that supports [Agent Skills](https://agentskills.io)
with the GNADD skills installed (`help-gnadd`, `audit-gnadd`, `prime-gnadd`, `new-issue-gnadd`,
`start-issue-gnadd`, `commit-gnadd`, `resolve-issue-gnadd`, `quickfix-gnadd`, `yolo-gnadd`),
the GitHub CLI (`gh`) installed and authenticated, and a GitHub account.

**Install skills:** see [README.md](README.md).

---

## Part 1 — Starting a Project

### The rule that sorts your old habits

If you're coming from a spec-plus-markdown-task-list workflow, one rule decides
what survives:

> **Files that *describe* stay. Files that *track* go.**

The whole reason this workflow exists is that mutable state in markdown —
checkboxes, statuses, "current progress" notes — goes stale and quietly poisons
agent context. Stable reference text the agent merely reads has none of that
problem. Applied to the usual kit:

| Old artifact | Fate | Where it went |
|---|---|---|
| Task list (`tasks.md`, `TODO.md`) | **Gone, fully** | The GitHub issue list *is* the task list. Adding a task is `/new-issue-gnadd`; seeing the list is `/prime-gnadd`; "in progress" is a branch existing; "done" is a merged PR. Task state is a side effect of doing the work, not a separate bookkeeping chore. |
| Progress / session-state file | **Gone, fully** | Git itself. Commits are save points, the branch tells you what's mid-flight, and `/prime-gnadd` reconstructs "where was I" from reality instead of from a note that may or may not reflect it. |
| Decisions file (`decisions.md`, ADRs) | **Mostly gone, relocated** | Decisions made *while implementing* go in the PR body for that work — permanently attached to the exact change they explain. Scope decisions ("we're deliberately not doing X") go in the issue's Constraints/Non-goals section. The rare cross-cutting decision no single PR owns can live in the README. |
| Spec / PRD | **Keep a thin one, demoted** | A short README: vision (what this is, for whom) plus a **"What done looks like"** section holding the project-level acceptance criteria as *statements*. It is *not* the thing the agent decomposes, checks progress against, or updates as it goes. Satisfaction *state* is never stored here — it's derived from the issue/PR record. See "Where the higher-order requirements live" below. |

A project-conventions file (`AGENTS.md`, agent rules) is also fine to keep — it's
read-only orientation, not state.

And when you're unsure about any file:

> **Would the agent need to keep this up to date?** If yes, it shouldn't exist —
> that state has a home in GitHub. If the agent only ever reads it, it's harmless.

### What about the design phase?

If a project needs real upfront thinking — architecture, tradeoffs, shape — do
that thinking **in conversation** with the agent. If the ideation phase naturally
produces a `requirements.md` (or it's needed as input to a formal design process),
that's fine: a requirements doc is a legitimate **phase artifact with an expiry**,
not a violation of the rule. Its lifecycle:

1. **Created** during ideation — high-level objectives, desired end state, even
   with details unknown.
2. **Consumed** by the design phase as input.
3. **Distilled** when development starts: stable conclusions into the README's
   "What done looks like" section, actionable specifics into the first issues'
   Context sections.
4. **Archived** — dated ("requirements as of project start") or deleted. It must
   never linger as a half-authoritative document agents read after reality has
   diverged from it, and it is never the live spec the loop runs against. Issues
   are that.

What stays forbidden is the *maintained* design document — one the agent is
expected to keep current as the project evolves. That's a tracking file in
disguise.

### Where the higher-order requirements live

Project-level requirements feel like one thing but are two, and the traditional
PRD rots because it fuses them:

- **The statements** ("the project succeeds when users can do X") are
  describe-content: they change rarely, by deliberate human decision. They live in
  the README's **"What done looks like"** section, written with the same discipline
  as issue criteria — observable, behavioral — just at higher altitude.
- **The satisfaction state** (which statements are true yet) is track-content: it
  changes constantly as a side effect of work. It is **never stored in a file** —
  it's derived from the issue and PR record. For a finer-grained view, GitHub
  **milestones** are the native middle layer: map a project-level criterion to a
  milestone, attach issues to it, and completion computes itself from issue state.
  Optional at small scale; useful once many open issues serve several distinct
  goals.

When a project-level requirement itself changes — a pivot, a descope — **route the
change through the loop**: make it an issue ("Revise project scope: drop offline
support"), whose observable outcome is the updated README and whose PR body
carries the rationale. The README only ever states current truth; the history of
how the truth changed lives where all decision history lives — in merged PRs.

### The startup sequence

1. **Create the repo on GitHub first.** Remote, `main` branch, `gh` authenticated.
   The workflow assumes GitHub exists from minute one — there's no offline phase.
2. **Turn on the server-side rails.** Run `gnadd.sh init` once (the script is
   bundled with the operational skills; add `--ci` to also drop in a minimal test
   workflow). It configures the repo so the two most important invariants are
   enforced by GitHub itself, not by anyone's discipline: merges are squash-only
   with the PR body as the commit message, merged branches auto-delete, and a
   ruleset on `main` requires a PR and blocks force pushes and deletion. After
   this, the worst case for most mistakes is an error message, not lost work.
   (Default keeps an admin bypass as a solo escape hatch; `--strict` removes it.)
3. **Write the thin README.** A few paragraphs of vision, plus a "What done looks
   like" section with the project-level criteria as statements. Resist making it a
   PRD — no checkboxes, no status, no plan.
4. **Capture the first few issues with `/new-issue-gnadd`** — and here's the habit change
   that will feel most wrong at first: *don't* front-load the whole backlog the way
   you'd write a full `tasks.md`. Write the first three or four vertical slices and
   stop. Issues are cheap to add at any moment — `/new-issue-gnadd` works mid-conversation
   and mines the discussion — and a 30-issue upfront breakdown is just your old
   speculative task list wearing a new costume. Half of it will be wrong by issue
   six.
5. **Make the first issue a walking skeleton.** "Project runs end-to-end and does
   one trivial thing" is a legitimate vertical slice — repo scaffold, hello-world
   behavior, maybe deploy. It gets the loop turning immediately.
6. **`/start-issue-gnadd 1`** and you're in the development loop.

**Adopting GNADD on an existing repo?** Run `/audit-gnadd` first — it reviews
context files and workflow alignment, then proposes minimal fixes to capture as
issues before you enter the loop.

---

## Part 2 — The Development Loop

Every piece of work moves through the same five commands.

### 1. `/prime-gnadd` — start every session here

Read-only and always safe. It fetches the latest from GitHub and reports: what the
project looks like, what branch you're on, open issues, PRs in flight, what
recently shipped. Three things in its output deserve attention:

- A **"main has diverged"** warning — stop and sort that out before anything else.
- A **stash warning** — you have invisible saved work; deal with it or it will be
  forgotten.
- **PRs awaiting review** — someone's waiting on you.

### 2. `/new-issue-gnadd` — when you have work to capture

The skill interviews you, one question at a time, until it can write the issue.
Your only job: describe **what** should happen and **why** — observable behavior,
not implementation. "Users can search and see results," not "build the search data
layer." If you catch yourself dictating *how*, the skill will redirect you; let
it. It will also flag when you're bundling several issues into one — take the
split. You approve the draft before anything is created.

### 3. `/start-issue-gnadd <N>` — when you're ready to work

It branches off main, loads the issue as your working spec, and proposes an
ordered plan derived from the acceptance criteria. Review it — confirm, correct
intent, or redirect — before any implementation begins; say "go" when the plan
looks right. If you have uncommitted changes lying around, it stops and asks
what to do with them: **choose "commit" unless you have a specific reason not
to** — a commit is visible and recoverable; a stash is invisible and easy to
lose. If you already started editing files before remembering to run this
(everyone does), don't worry: it carries your changes onto the new branch safely.

### 4. `/commit-gnadd` — early and often while working

These are save points; they're cheap, and you can have many per issue. The skill
shows you what changed, flags anything suspicious (credentials, logs, scratch
files), drafts a message, and waits for your approval. You can also just say
"commit this" mid-conversation.

### 5. `/resolve-issue-gnadd` — when the work feels done

The skill checks the actual changes against the issue's acceptance criteria and
tells you what's met, unmet, or descoped — and runs the project's test suite,
reporting results alongside. Don't wave past unmet items or failing tests
silently — either finish them or explicitly accept the gap. It then drafts the
final commit and a PR, and asks whether to merge.

If you leave the PR open instead of merging, that's fine: running
`/resolve-issue-gnadd` on the branch later picks up at the merge gate automatically —
it will never try to create a second PR.

**This is the moment that matters most: read the diff before you say "merge
now."** AI-written changes read as confident and can hide subtle errors; the
entire system's safety rests on a human actually looking at what's about to land.

Two more habits at this gate:

- If you made a non-obvious decision during the work, put the *why* in the PR
  body. Chat evaporates; PRs are permanent.
- Note the merge commit hash it reports — that's your one-command undo for the
  whole feature if it ever comes to that.

After your go-ahead it merges, syncs the issue checkboxes, cleans up the branch,
and reports back. Then `/prime-gnadd` next session, and the loop continues.

### Mid-work issue updates (provisional — still under evaluation)

In practice it often feels natural to tell the agent, mid-work, to check off
completed acceptance criteria on the issue or add a note for something descoped
or pivoted away from. This is **allowed and principled** — the issue is exactly
where that state belongs, and capturing a descope decision the moment it happens
beats reconstructing it at resolve time. Two conditions keep it sound:

- **Keep it opportunistic, never ritual.** Update when it feels natural. The moment
  it becomes a required step after every change, you've recreated the bookkeeping
  chore this workflow exists to kill. The guaranteed sync point is `resolve-issue-gnadd`.
- **A checked box is a claim, not a fact.** Work done after you check it can break
  it. `resolve-issue-gnadd` re-verifies every criterion against the actual diff regardless
  of checkbox state — that re-verification is what makes mid-work checking safe.

Whether this practice earns a dedicated skill is an open question — see
`update-issue` in Part 5's deferred-skills list for the trigger that would decide it.

---

## Part 3 — Rules of the Road

**When a skill stops with a warning, that's the system working — not breaking.**
The skills are built to halt rather than guess whenever git is in a state that
could lose work: a diverged main, a merge conflict, a pull that won't
fast-forward. When that happens: read what it tells you, pick from the options it
offers, and ask for an explanation if the options don't make sense.

Two things to never do:

1. **Don't let an agent talk you into an improvised fix** involving `reset`,
   `force`, or resolving a conflict "real quick." Those are precisely the
   operations this workflow exists to keep away from improvisation. A failure
   followed by a stop is the system working.
2. **Don't run raw git commands from outside the skills.** The server and script
   rails still stand, but the judgment gates don't. If something seems to need a
   git operation no skill covers, ask "is there a skill-shaped way to do this?"
   first — and for recovering from a bad state, `gnadd.sh doctor` is the answer
   (see Recovery below).

**Merge conflicts** are rare and deliberately a human event: the agent will never
resolve one for you. Resolve it in GitHub's web editor, or ask for a step-by-step
walkthrough.

### Recovery — the sanctioned path out of a bad state

"Halt and don't improvise" only works as a policy if there's a vetted road back.
That road is `gnadd.sh doctor` (bundled with the `prime-gnadd` skill). Run with no
arguments it diagnoses every known bad state and prints the one safe recipe for
each; it changes nothing on its own. The recipes:

- **Diverged `main`** (local commits origin lacks): `gnadd.sh doctor
  --rescue-main rescue/<desc>`. It bookmarks the stray commits on a rescue
  branch, verifies the bookmark, then realigns `main` to origin — lossless by
  construction, and it never uses `reset`. You end up standing on the rescue
  branch; route it through an issue and PR like any other work.
- **Stashed work you forgot about:** `git stash branch rescue/<desc>` turns the
  newest stash into a visible branch.
- **Dirty tree on `main`:** `/start-issue-gnadd` carries it onto a fresh issue branch.
- **Detached HEAD:** `git switch -c rescue/<desc>` makes the commits a real branch.
- **Leftover issue branches** from an interrupted cleanup: doctor identifies
  them; `gnadd.sh cleanup <pr> <branch>` deletes only after GitHub confirms the
  merge.

Everything doctor does is additive — it creates branches, it never deletes or
rewrites. If a state falls outside this list, that's the moment to stop and ask
for help, not to accept an improvised `reset`/`force` fix.

### The short version

Prime first. Describe what, not how. Slice thin and don't front-load the backlog.
Commit often. Read the diff. Treat every skill warning as real. Keep files that
describe; kill files that track. The rails catch nearly every mistake you can make
inside them — the one they can't catch is merging without looking.

---

## Part 4 — Reference

### The enforcement layers

Every invariant lives at the **lowest layer that can hold it** — the further down,
the harder the guarantee:

| Layer | Holds | Failure mode if bypassed |
|---|---|---|
| **GitHub server** (`gnadd.sh init`) | Squash-only merges, PR required on `main`, no force pushes, no branch deletion, auto-delete merged branches | Server rejects the operation |
| **Script** (`gnadd.sh`, bundled in skills; canonical `bin/gnadd`, tested by `test/run.sh`) | Working-tree protection before checkout, ff-only syncs, divergence halts, merge-verified cleanup, conflict refusal | Command exits with `state=<NAME>`; nothing was touched |
| **Skills** | Judgment gates: scope questions, plan approval, staging choices, merge confirmation | Agent asks instead of acting |
| **Human** | Reading the diff before merge | No layer below can catch this |

The script speaks a fixed protocol: `key=value` facts on success, `state=<NAME>`
plus context and exit code 2 whenever a human decision is needed. A `state=` halt
is the system working. The named states: `DIRTY_TREE`, `DIVERGED_MAIN`,
`FF_REFUSED`, `BRANCH_DIVERGED_FROM_REMOTE`, `ON_MAIN`, `DETACHED_HEAD`,
`NOT_ISSUE_BRANCH`, `NOTHING_TO_SHIP`, `PR_CONFLICTING`, `MERGEABILITY_UNKNOWN`,
`NOT_MERGED`, and a few rarer ones — each skill documents the conversation for
the states it can encounter.

### The skills

All seven are global skills when installed with `-g` (available in every repo). The
seven operational skills drive the loop — their git mechanics run through the
bundled `gnadd.sh` script, not improvised commands; `help-gnadd` provides
lightweight workflow orientation; `audit-gnadd` reviews alignment when adopting
or realigning a repo. Operational skills are invoked explicitly except `commit-gnadd`,
which can also trigger on "commit this" or similar.

| Skill | Invocation | Source | Does |
|---|---|---|---|
| `help-gnadd` | Auto when workflow-shaped; `/help-gnadd` | `skills/help-gnadd/SKILL.md` | Orient agents on the GNADD model, describe-vs-track file rule, skill routing, and pinned canonical guide |
| `audit-gnadd` | `/audit-gnadd` | `skills/audit-gnadd/SKILL.md` | Read-only alignment audit: scrutinize context files, shallow git/workflow check, report minimal fixes |
| `prime-gnadd` | `/prime-gnadd` | `skills/prime-gnadd/SKILL.md` | Orient a new session: fetches remote, reports project shape, branch state, whether main is behind or diverged, stashes, open issues, open + merged PRs |
| `new-issue-gnadd` | `/new-issue-gnadd` | `skills/new-issue-gnadd/SKILL.md` | Draft a behavioral issue (with acceptance criteria) and create it after review |
| `start-issue-gnadd` | `/start-issue-gnadd <N>` | `skills/start-issue-gnadd/SKILL.md` | Protect in-progress work, branch off main, load the spec, propose a plan, wait for approval |
| `commit-gnadd` | `/commit-gnadd` or "commit this" | `skills/commit-gnadd/SKILL.md` | Stage and commit with a conventional message; references the issue with `Re #N`; guards main |
| `resolve-issue-gnadd` | `/resolve-issue-gnadd` | `skills/resolve-issue-gnadd/SKILL.md` | Verify against criteria, commit, PR, check mergeability + CI, merge, clean up |
| `quickfix-gnadd` | `/quickfix-gnadd` | `skills/quickfix-gnadd/SKILL.md` | Land one trivial change via a CI-gated squash-merged PR, no issue; guard refuses large or mechanics-touching diffs |
| `yolo-gnadd` | `/yolo-gnadd <N or description>` (explicit only) | `skills/yolo-gnadd/SKILL.md` | Run one decided issue or quickfix through the whole loop autonomously: gates auto-approved, independent review pass, CI-gated merge, trace-backed report |

### The core principles

- **Issues describe *what* and *why*, never *how*.** Implementation decisions happen
  in conversation during work, not upfront in the spec. The exception is a Context
  section (orientation, not instructions).
- **Acceptance criteria are the definition of done.** They state observable conditions
  a reviewer could check *without reading the code*. They are written in `new-issue-gnadd`,
  surfaced in `start-issue-gnadd`, and verified in `resolve-issue-gnadd` — the same contract,
  carried end to end.
- **Vertical slices over horizontal layers.** Each issue delivers a thin, end-to-end,
  observable behavior. "Users can search and see results" — not "build the search
  data layer."
- **Context is loaded on demand, not speculatively.** `prime-gnadd` gives the map.
  `start-issue-gnadd` gives the terrain. Source files are read when the work needs them.
- **The PR is the record of what actually shipped.** If the outcome diverged from the
  issue, the PR body says so. Implementation *decisions* belong here too — this is how
  reasoning made in chat survives into git.
- **The agent never silently loses commits, resets main, or resolves conflicts
  autonomously.** These are hard rules in the skills, not aspirations.

### The lifecycle

```
/prime-gnadd            → orient: where things stand, what's behind, what's open
/new-issue-gnadd        → capture intent as a behavioral spec + acceptance criteria
/start-issue-gnadd <N>  → branch off main, load the spec, propose plan, get approval
  …work, /commit-gnadd frequently as save points…
/resolve-issue-gnadd    → verify against criteria → PR → check mergeability + CI → merge → clean up
/prime-gnadd            → next session: your merged PR shows as shipped, pick the next issue
```

### Branching and history model

- Branches are named `issue-<N>/<slug>` and are short-lived.
- Main moves forward by **squash-merge**: each issue becomes exactly one commit on
  main. After `gnadd.sh init`, this is repo policy, not convention — merge commits
  and rebase-merges are disabled, and the PR body becomes the squash commit's
  message, so the decision record lands in git history itself.
- There is **no local rebase** before merging (see Part 5 for why). GitHub computes
  mergeability; if a real conflict exists, it is handed to the user, never auto-resolved.
- Every merged PR is a rollback unit: `git revert <merge-hash>` undoes one feature.
  `resolve-issue-gnadd` reports that hash at merge time for exactly this reason.
- Merged branches auto-delete on GitHub; local cleanup is gated on GitHub
  confirming the merge.

### Commit message format

```
<type>: <concise summary>

<optional body>
Re #<N>      ← mid-work commits (a save point)
```

The final PR uses `Closes #<N>` instead of `Re #<N>`. Types: `feat`, `fix`, `chore`,
`docs`, `refactor`, `test`, `style`, `perf` — chosen from the actual change, not the
issue label.

### Behind vs. diverged (the one git concept worth internalizing)

The skills protect main aggressively, and they distinguish two states. Knowing the
difference will keep you from panicking at a normal message or ignoring a real one:

- **Behind** (safe, normal): origin has commits your local main doesn't; your local
  main has nothing extra. Right after every merge, your local main is behind by exactly
  the commit you just merged. A plain pull catches you up cleanly. No action needed
  beyond pulling.
- **Diverged** (dangerous, rare): your local main has commits that are *not* on origin —
  usually a sign something was committed straight to main or its history was rewritten.
  A plain pull can't reconcile this. The skills will **stop** and hand it to you
  rather than guess. If you see this, it's worth asking for help rather than
  improvising.

The skills watch for the dangerous direction specifically, at every point where they
touch main, and all pulls onto main are fast-forward-only. If a skill ever halts and
says main has diverged, that's the real thing — don't wave it through.

### The mistakes the system catches (and the ones it can't)

Caught by the skills — you'll be stopped and offered a safe path, so these are
recoverable, not catastrophic:

- **Editing before starting the issue.** You open the project, change files while on `main`,
  then remember `/start-issue-gnadd`. The skill carries your changes onto the new issue branch
  rather than committing them to `main`. The most likely mistake, fully recoverable.
- **"Commit this" while on `main`.** `commit-gnadd` stops and asks; it won't quietly put work
  on local `main`.
- **Running `/resolve-issue-gnadd` on the wrong branch.** The skill verifies the branch before
  committing or pushing anything; from `main` it refuses outright.
- **A diverged `main`, however it happened.** `prime-gnadd`, `start-issue-gnadd`, and `resolve-issue-gnadd`
  all detect it and stop; every pull onto `main` is fast-forward-only.

Not catchable by skills — these live with you (though after `gnadd.sh init`,
the server catches the worst versions):

- **Merging without reading the diff.** Still the load-bearing human habit; nothing
  below the human can replace it.
- **Running raw git commands outside the skills**, including ones an agent suggests
  mid-conversation. The script and server rails still stand, but judgment gates
  don't. If a git operation seems needed and no skill covers it, prefer asking
  "is there a skill-shaped way to do this?" — and for known bad states,
  `gnadd.sh doctor` is the sanctioned answer.
- **Approving an agent's improvised fix when a git command fails.** Failures inside
  skills are designed to stop and report. If an agent instead proposes a reset, a
  force-push, or on-the-fly conflict resolution, that is the moment to slow down — those
  are exactly the operations this workflow exists to keep away from improvisation.
  (With the `init` ruleset in place, a force-push to `main` fails at the server
  even if approved.)

---

## Part 5 — Design Decisions & Rationale

This is the anti-drift log. Each entry records a deliberate choice and why it was made,
so the reasoning doesn't evaporate and get "helpfully" reverted later. If you're about
to change one of these, read the rationale first — it may already address your concern.
With no separate change log (git history covers that), these entries are also where the
workflow's history lives.

### Mechanics live in code, not prose (2026-07)
**Decision:** Every git sequence the workflow depends on moved from SKILL.md prose
into a single tested script — canonical at `bin/gnadd`, copied verbatim into each
operational skill as `gnadd.sh` by `scripts/build.sh` (so installed skills are
self-contained), with `test/run.sh` failing if the copies drift. Skills now hold
judgment and conversation; the script holds mechanics and halts with `state=<NAME>`
at every human decision point.
**Why:** Prose instructions are re-performed from memory by an agent on every
invocation — each run is a fresh chance to typo, skip a step, or improvise a
variant, and none of it is testable. Code runs the same way every time, on any
agent, and every guarantee ("cleanup never deletes an unmerged branch") is now a
regression test rather than a hope. This is the same insight the workflow was
founded on, applied to its own safety layer: state belongs in git, not markdown;
invariants belong in code, not prompts.
**Rule:** never edit `skills/*/gnadd.sh` directly — edit `bin/gnadd`, run
`scripts/build.sh`, and keep `test/run.sh` green. When a skill and the script
disagree on a mechanical detail, the script wins.

### Server-side rails via `gnadd init` (2026-07)
**Decision:** `gnadd.sh init` configures the repo itself: squash-only merges,
squash commit message = PR title + body, delete-branch-on-merge, and a ruleset on
`main` requiring a PR and blocking force pushes and deletion. Default keeps an
admin bypass (solo escape hatch); `--strict` removes it.
**Why:** The two most dangerous outcomes — unreviewed work landing on `origin/main`
and history rewrites of `main` — were previously prevented only by agents following
instructions. The server can reject both outright, which converts a diverged local
`main` from "dangerous" to "unpushable" and makes squash-discipline a fact rather
than a convention. PR_BODY as the squash message also puts the PR's decision record
into git history itself, strengthening "the PR is the record."
**Note:** this supersedes the old habit of committing small doc fixes directly to
`main`. If the loop feels too heavy for a typo, that is the trigger for the
deferred `quick` skill — build the fast path, don't keep the side door.

### Doctor is the sanctioned recovery path (2026-07)
**Decision:** `gnadd.sh doctor` diagnoses the known bad states (diverged main,
stashes, dirty main, detached HEAD, leftover branches) and offers exactly one
vetted recipe per state. Its only mutating action, `--rescue-main`, bookmarks the
stray commits on a rescue branch, verifies the bookmark, steps onto it, and moves
the `main` ref back to origin with `branch -f` — additive at every step, no
`reset`, no force-push, nothing deleted.
**Why:** The old rule was "halt and don't let the agent improvise," with no
sanctioned path out — so the actual behavior at halt time would have been exactly
the improvisation the rule forbids. A recovery tool written and tested while calm
beats a recipe invented mid-incident. The "never reset main" hard rule stands
unchanged; rescue-main achieves realignment without any history-destroying
operation.

### No local rebase before merging
**Decision:** `resolve-issue-gnadd` does not rebase the issue branch onto main. It pushes,
opens a PR, and lets GitHub's squash-merge apply the work as one commit on current main.
Conflicts are detected via `gh pr view --json mergeable` and handed to the human.
**Why:** Squash-merge already produces one commit per feature on top of latest main, so
a local pre-rebase is largely redundant. Rebase is the single most dangerous git
operation to hand an agent — it rewrites history and forces a force-push, which is the
exact class of operation behind an earlier incident where an agent reset main and
dropped a commit. For a small repo, the benefit of rebase (strictly linear,
bisect-grade history) is almost never cashed in, while the risk is constant.
**Reversible:** If the repo grows to a team that bisects main, a pre-rebase step can be
reintroduced — but it must come with a hard `git push --force-with-lease` rule (never
bare `--force`) and explicit rebase-abort handling. Don't add it back casually.

### Squash-merge (accepting the bisect tradeoff)
**Decision:** Every PR squash-merges to one commit on main.
**Why:** Makes each feature an atomic rollback unit (`git revert <merge-hash>`) and keeps
main readable. **Known cost:** `git bisect` lands on a fat squash commit, not the
offending line. Mitigation is detailed PR bodies, so the squash commit is
self-documenting. For a small repo's scale, bisect is rare and the tradeoff is worth it.

### `git branch -D` (not `-d`) after merge, gated on a merge check
**Decision:** `resolve-issue-gnadd` cleanup deletes the branch with `-D` (force), but only
after confirming via `gh pr view --json state,mergedAt` that the PR actually merged.
**Why:** After a *squash*-merge, the branch's commits are not ancestors of main, so git's
safe delete (`-d`) refuses every time — it would fail on every successful resolve. `-D`
is correct here, and the merge-state check is what makes it provably non-destructive:
if the PR merged, the work is on main, so the branch is genuinely redundant.
**Do not** revert this to `-d`; it will break on every merge.

### Main-safety: stop only on the *dangerous* divergence direction
**Decision:** After merge, `resolve-issue-gnadd` pulls main when "behind," and stops only when
`git log origin/main..main` (local-ahead) shows commits.
**Why:** A naive check that stops whenever local and origin differ would halt on *every*
merge, because being behind by the just-merged commit always shows a difference. That
would make the safety warning fire constantly and train the user to ignore it —
defeating its purpose. The genuinely dangerous state is local main holding commits
origin lacks (`origin/main..main` non-empty); being behind (`main..origin/main`
non-empty) is the normal, safe, fast-forwardable state. Verified empirically.
**Companion hard rule:** never `git reset` on main to discard commits, in any form.
**Extended (2026-06):** the behind-vs-diverged classification now runs at **every** main
touchpoint, not just resolve time: `prime-gnadd` reports divergence as a prominent warning,
`start-issue-gnadd` classifies before its fresh-start pull, and all pulls onto `main` (and
onto issue branches at resume) use `--ff-only` — so a merge commit on main is
mechanically impossible even if a classification step is somehow missed.

### Skills verify the *branch*, not just the issue
**Decision:** `resolve-issue-gnadd` refuses to run from `main` or detached HEAD and requires an
explicit, working-tree-safe switch to an issue branch. `commit-gnadd` stops and requires
explicit confirmation before committing on `main` or in detached HEAD. `start-issue-gnadd`
never commits rescued changes to `main` — a dirty tree on `main` at fresh start is
carried onto the new issue branch via `checkout -b` (which preserves the working tree).
**Why:** The original `resolve-issue-gnadd` asked "which issue?" when the branch didn't match —
then operated on the *current* branch anyway. Invoked from `main`, that path would
commit and push directly to `origin/main`, shipping unreviewed work around the PR gate:
the only such path in the system, reachable by one wrong answer to an innocuous
question. Likewise `commit-gnadd`, the only auto-triggerable skill, could create local-main
divergence from a casual "commit this." The fix is one idea applied everywhere: **a
skill must confirm it is standing in the right place before it writes.** The dirty-main
carry exists because "started editing before starting the issue" is the most likely
human mistake in the whole workflow, and `checkout -b` from main is a provably lossless
rescue for it.

### Acceptance criteria must be behavioral, not implementation
**Decision:** `new-issue-gnadd` writes acceptance criteria as observable conditions checkable
without reading code; mechanisms are explicitly disallowed.
**Why:** Criteria are where "how" tries to sneak past the "what-not-how" principle.
"Results appear within 1 second" is a fine criterion; "uses a debounced input" is
implementation leaking in. Keeping criteria behavioral preserves the core principle
while still giving `resolve-issue-gnadd` something concrete to verify against.

### `commit-gnadd` deliberately does NOT cross-check against the issue spec
**Decision:** Drift-detection (does this change match the issue?) lives in
`resolve-issue-gnadd`, not `commit-gnadd`.
**Why:** `commit-gnadd` is the highest-frequency action; its value is being fast and
predictable. Adding issue-fetching and drift-reasoning to every checkpoint commit would
add friction and constant false positives (mid-work commits legitimately touch
not-yet-on-spec scaffolding). Drift is caught once, at resolve time, before it ships.

### `start-issue-gnadd` checks the working tree *before* any checkout
**Decision:** The in-progress-work safety check runs before resuming or creating any
branch, including before checking out an existing issue branch.
**Why:** An earlier ordering checked out the resume branch first, which could fail or
silently carry uncommitted changes onto the wrong branch — the quiet-data-movement bug
the whole workflow is meant to design out. Protecting the working tree first closes it.

### prime-gnadd fetches remote state (and stays read-only)
**Decision:** `prime-gnadd` runs `git fetch --prune` and surfaces behind-count, divergence,
stashes, and open PRs.
**Why:** Without a fetch, prime-gnadd reports a stale local cache — invisible to collaborators'
pushes and blind to local main being behind. `fetch --prune` updates remote-tracking
refs only; it touches no working files or branches, so it honors prime-gnadd's read-only
contract.

### YOLO mode trades the pre-merge human review — deliberately (2026-07)
**Decision:** `yolo-gnadd` runs one already-decided issue or quickfix through the
entire loop with the mid-loop gates (plan approval, staging confirmation,
PR-draft approval, merge confirmation) auto-approved. What substitutes for the
human's pre-merge diff review: the pre-approved spec as the contract, an
independent fresh-context review pass recorded in the PR (every finding marked
addressed or dismissed-with-reason), the script-enforced CI gate, and post-merge
revertability via the squash commit. Three hard boundaries: every `state=` halt,
guard refusal, and CI failure remains a stop (with a 2-round self-repair budget
before escalating); a diff touching `bin/`, `scripts/`, `.github/`, or a
`gnadd.sh` copy is never merged autonomously — the run stops at the merge gate;
and YOLO never chooses its own work — explicit invocation on a decided unit is
the consent.
**Why:** Once the spec is human-approved, the mid-loop gates mostly rubber-stamp
what the spec already authorized, while each round-trip costs a session
interruption. The rails that made this safe to trade were built first — server-side
PR requirement, script-owned merge path, one-command revert. The review moves,
it doesn't disappear: post-merge skim-and-revert, armed by a closing report.
**Enforcement is structural, not promised:** yolo contains no loop mechanics of
its own — each phase is executed by loading the sibling skill — and every
`gnadd.sh` invocation leaves a receipt line in `.git/gnadd-trace.log` (`gnadd
trace show`). The closing report must include the trace and call out any gaps;
a freewheeled run is visible, not deniable.

### Skills deferred (not built speculatively)
- **`update-issue`** (mid-work issue sync: check off completed acceptance criteria,
  add descope/pivot notes): currently done ad hoc by instructing the agent, which
  works. Build when ad hoc starts failing — a mangled issue body (`gh issue edit
  --body` replaces the *whole* body, so a casual edit can drop sections or clobber
  a collaborator's web-UI change) or visibly inconsistent note formats. The skill's
  value is encoding "fetch the body fresh, minimal edit, preserve everything else
  verbatim" plus one consistent descope-note shape.
- **`update-pr`** (respond to PR review feedback): build when a collaborator first
  requests changes and the real shape is known. A separate need from `update-issue`.
  (The narrower "merge the PR I left open yesterday" case is already covered:
  `resolve-issue-gnadd` detects an existing open PR and resumes at the merge gate.)
- **`quick`** — landed as `quickfix-gnadd` (2026-07): the micro-task overhead
  trigger fired in practice. One trivial change per invocation, no issue (the PR
  is the record), with a deterministic guard (small diffs only; never `bin/`,
  `scripts/`, `.github/`, or `gnadd.sh` copies) and a CI-gated squash merge
  enforced in the script. A fast path *through* the safety rails, not around them.
- **Hard CI gate** in `resolve-issue-gnadd`: partially landed — `resolve-issue-gnadd` runs the
  project's test suite locally via `gnadd.sh test` before the PR, and `gnadd.sh
  init --ci` bootstraps a GitHub Actions workflow. Make the GitHub-side check
  *blocking* (not just reported at the merge gate) once a project's CI is stable
  enough to trust.
