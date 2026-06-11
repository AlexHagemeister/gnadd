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
| **Skills** | `skills/<name>/SKILL.md` in this repo | The exact commands, gates, and sequences the agent runs | Claude |
| **Skills (installed)** | Agent skills dir via `npx skills add` | Runtime copy your agent loads | Install once; `npx skills update` to refresh |
| **This doc** | `GNADD.md` in this repo | The model, the rationale, and how to drive it | Claude |
| **Instructions** | Claude Desktop settings (a pointer to this doc) | Telling Claude this doc exists | You (once) |

The skills carry operational detail. This doc deliberately does **not** restate every
git command — that would create two copies that drift apart. It points at the skills
for mechanics and concentrates on the things a skill can't hold: the model, the
human's role, and the reasoning behind the design.

---

## The model in three sentences

GitHub is the entire project-management system: **issues** say what to build,
**branches** are where work happens, **PRs** record what shipped. You don't need
to know git — five skills run every git operation and stop to ask you
whenever a decision matters. Your job is to describe work well, answer the skills'
questions deliberately, and read diffs before merging.

**Prerequisites:** A coding agent that supports [Agent Skills](https://agentskills.io)
with the GNADD skills installed (`gnadd-context`, `gnadd-audit`, `prime`, `new-issue`,
`start-issue`, `commit`, `resolve-issue`), the GitHub CLI (`gh`) installed and
authenticated, and a GitHub account.

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
| Task list (`tasks.md`, `TODO.md`) | **Gone, fully** | The GitHub issue list *is* the task list. Adding a task is `/new-issue`; seeing the list is `/prime`; "in progress" is a branch existing; "done" is a merged PR. Task state is a side effect of doing the work, not a separate bookkeeping chore. |
| Progress / session-state file | **Gone, fully** | Git itself. Commits are save points, the branch tells you what's mid-flight, and `/prime` reconstructs "where was I" from reality instead of from a note that may or may not reflect it. |
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
2. **Write the thin README.** A few paragraphs of vision, plus a "What done looks
   like" section with the project-level criteria as statements. Resist making it a
   PRD — no checkboxes, no status, no plan.
3. **Capture the first few issues with `/new-issue`** — and here's the habit change
   that will feel most wrong at first: *don't* front-load the whole backlog the way
   you'd write a full `tasks.md`. Write the first three or four vertical slices and
   stop. Issues are cheap to add at any moment — `/new-issue` works mid-conversation
   and mines the discussion — and a 30-issue upfront breakdown is just your old
   speculative task list wearing a new costume. Half of it will be wrong by issue
   six.
4. **Make the first issue a walking skeleton.** "Project runs end-to-end and does
   one trivial thing" is a legitimate vertical slice — repo scaffold, hello-world
   behavior, maybe deploy. It gets the loop turning immediately.
5. **`/start-issue 1`** and you're in the development loop.

**Adopting GNADD on an existing repo?** Run `/gnadd-audit` first — it reviews
context files and workflow alignment, then proposes minimal fixes to capture as
issues before you enter the loop.

---

## Part 2 — The Development Loop

Every piece of work moves through the same five commands.

### 1. `/prime` — start every session here

Read-only and always safe. It fetches the latest from GitHub and reports: what the
project looks like, what branch you're on, open issues, PRs in flight, what
recently shipped. Three things in its output deserve attention:

- A **"main has diverged"** warning — stop and sort that out before anything else.
- A **stash warning** — you have invisible saved work; deal with it or it will be
  forgotten.
- **PRs awaiting review** — someone's waiting on you.

### 2. `/new-issue` — when you have work to capture

The skill interviews you, one question at a time, until it can write the issue.
Your only job: describe **what** should happen and **why** — observable behavior,
not implementation. "Users can search and see results," not "build the search data
layer." If you catch yourself dictating *how*, the skill will redirect you; let
it. It will also flag when you're bundling several issues into one — take the
split. You approve the draft before anything is created.

### 3. `/start-issue <N>` — when you're ready to work

It branches off main, loads the issue as your working spec, and asks where you
want to start. If you have uncommitted changes lying around, it stops and asks
what to do with them: **choose "commit" unless you have a specific reason not
to** — a commit is visible and recoverable; a stash is invisible and easy to
lose. If you already started editing files before remembering to run this
(everyone does), don't worry: it carries your changes onto the new branch safely.
Then discuss the approach in chat, or just say "go."

### 4. `/commit` — early and often while working

These are save points; they're cheap, and you can have many per issue. The skill
shows you what changed, flags anything suspicious (credentials, logs, scratch
files), drafts a message, and waits for your approval. You can also just say
"commit this" mid-conversation.

### 5. `/resolve-issue` — when the work feels done

The skill checks the actual changes against the issue's acceptance criteria and
tells you what's met, unmet, or descoped. Don't wave past unmet items silently —
either finish them or explicitly accept the gap. It then drafts the final commit
and a PR, and asks whether to merge.

**This is the moment that matters most: read the diff before you say "merge
now."** AI-written changes read as confident and can hide subtle errors; the
entire system's safety rests on a human actually looking at what's about to land.

Two more habits at this gate:

- If you made a non-obvious decision during the work, put the *why* in the PR
  body. Chat evaporates; PRs are permanent.
- Note the merge commit hash it reports — that's your one-command undo for the
  whole feature if it ever comes to that.

After your go-ahead it merges, syncs the issue checkboxes, cleans up the branch,
and reports back. Then `/prime` next session, and the loop continues.

### Mid-work issue updates (provisional — still under evaluation)

In practice it often feels natural to tell the agent, mid-work, to check off
completed acceptance criteria on the issue or add a note for something descoped
or pivoted away from. This is **allowed and principled** — the issue is exactly
where that state belongs, and capturing a descope decision the moment it happens
beats reconstructing it at resolve time. Two conditions keep it sound:

- **Keep it opportunistic, never ritual.** Update when it feels natural. The moment
  it becomes a required step after every change, you've recreated the bookkeeping
  chore this workflow exists to kill. The guaranteed sync point is `resolve-issue`.
- **A checked box is a claim, not a fact.** Work done after you check it can break
  it. `resolve-issue` re-verifies every criterion against the actual diff regardless
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
2. **Don't run raw git commands from outside the skills.** The rails only exist
   inside them. If something seems to need a git operation no skill covers, ask
   "is there a skill-shaped way to do this?" first.

**Merge conflicts** are rare and deliberately a human event: the agent will never
resolve one for you. Resolve it in GitHub's web editor, or ask for a step-by-step
walkthrough.

### The short version

Prime first. Describe what, not how. Slice thin and don't front-load the backlog.
Commit often. Read the diff. Treat every skill warning as real. Keep files that
describe; kill files that track. The rails catch nearly every mistake you can make
inside them — the one they can't catch is merging without looking.

---

## Part 4 — Reference

### The skills

All seven are global skills when installed with `-g` (available in every repo). The
five operational skills handle mechanics; `gnadd-context` provides lightweight
workflow orientation; `gnadd-audit` reviews alignment when adopting or
realigning a repo. Operational skills are invoked explicitly except `commit`,
which can also trigger on "commit this" or similar.

| Skill | Invocation | Source | Does |
|---|---|---|---|
| `gnadd-context` | Auto when workflow-shaped; `/gnadd-context` | `skills/gnadd-context/SKILL.md` | Orient agents on the GNADD model, describe-vs-track file rule, skill routing, and pinned canonical guide |
| `gnadd-audit` | `/gnadd-audit` | `skills/gnadd-audit/SKILL.md` | Read-only alignment audit: scrutinize context files, shallow git/workflow check, report minimal fixes |
| `prime` | `/prime` | `skills/prime/SKILL.md` | Orient a new session: fetches remote, reports project shape, branch state, whether main is behind or diverged, stashes, open issues, open + merged PRs |
| `new-issue` | `/new-issue` | `skills/new-issue/SKILL.md` | Draft a behavioral issue (with acceptance criteria) and create it after review |
| `start-issue` | `/start-issue <N>` | `skills/start-issue/SKILL.md` | Protect in-progress work, branch off main, load the issue as the working spec |
| `commit` | `/commit` or "commit this" | `skills/commit/SKILL.md` | Stage and commit with a conventional message; references the issue with `Re #N`; guards main |
| `resolve-issue` | `/resolve-issue` | `skills/resolve-issue/SKILL.md` | Verify against criteria, commit, PR, check mergeability + CI, merge, clean up |

### The core principles

- **Issues describe *what* and *why*, never *how*.** Implementation decisions happen
  in conversation during work, not upfront in the spec. The exception is a Context
  section (orientation, not instructions).
- **Acceptance criteria are the definition of done.** They state observable conditions
  a reviewer could check *without reading the code*. They are written in `new-issue`,
  surfaced in `start-issue`, and verified in `resolve-issue` — the same contract,
  carried end to end.
- **Vertical slices over horizontal layers.** Each issue delivers a thin, end-to-end,
  observable behavior. "Users can search and see results" — not "build the search
  data layer."
- **Context is loaded on demand, not speculatively.** `prime` gives the map.
  `start-issue` gives the terrain. Source files are read when the work needs them.
- **The PR is the record of what actually shipped.** If the outcome diverged from the
  issue, the PR body says so. Implementation *decisions* belong here too — this is how
  reasoning made in chat survives into git.
- **The agent never silently loses commits, resets main, or resolves conflicts
  autonomously.** These are hard rules in the skills, not aspirations.

### The lifecycle

```
/prime            → orient: where things stand, what's behind, what's open
/new-issue        → capture intent as a behavioral spec + acceptance criteria
/start-issue <N>  → branch off main, load the spec, decide approach
  …work, /commit frequently as save points…
/resolve-issue    → verify against criteria → PR → check mergeability + CI → merge → clean up
/prime            → next session: your merged PR shows as shipped, pick the next issue
```

### Branching and history model

- Branches are named `issue-<N>/<slug>` and are short-lived.
- Main moves forward by **squash-merge**: each issue becomes exactly one commit on main.
- There is **no local rebase** before merging (see Part 5 for why). GitHub computes
  mergeability; if a real conflict exists, it is handed to the user, never auto-resolved.
- Every merged PR is a rollback unit: `git revert <merge-hash>` undoes one feature.
  `resolve-issue` reports that hash at merge time for exactly this reason.

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
  then remember `/start-issue`. The skill carries your changes onto the new issue branch
  rather than committing them to `main`. The most likely mistake, fully recoverable.
- **"Commit this" while on `main`.** `commit` stops and asks; it won't quietly put work
  on local `main`.
- **Running `/resolve-issue` on the wrong branch.** The skill verifies the branch before
  committing or pushing anything; from `main` it refuses outright.
- **A diverged `main`, however it happened.** `prime`, `start-issue`, and `resolve-issue`
  all detect it and stop; every pull onto `main` is fast-forward-only.

Not catchable by skills — these live with you:

- **Merging without reading the diff.** Still the load-bearing human habit; nothing
  below the human can replace it.
- **Running raw git commands outside the skills**, including ones an agent suggests
  mid-conversation. The rails only exist inside the skills. If a git operation seems
  needed and no skill covers it, prefer asking "is there a skill-shaped way to do this?"
  before pasting commands.
- **Approving an agent's improvised fix when a git command fails.** Failures inside
  skills are designed to stop and report. If an agent instead proposes a reset, a
  force-push, or on-the-fly conflict resolution, that is the moment to slow down — those
  are exactly the operations this workflow exists to keep away from improvisation.

---

## Part 5 — Design Decisions & Rationale

This is the anti-drift log. Each entry records a deliberate choice and why it was made,
so the reasoning doesn't evaporate and get "helpfully" reverted later. If you're about
to change one of these, read the rationale first — it may already address your concern.
With no separate change log (git history covers that), these entries are also where the
workflow's history lives.

### No local rebase before merging
**Decision:** `resolve-issue` does not rebase the issue branch onto main. It pushes,
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
**Decision:** `resolve-issue` cleanup deletes the branch with `-D` (force), but only
after confirming via `gh pr view --json state,mergedAt` that the PR actually merged.
**Why:** After a *squash*-merge, the branch's commits are not ancestors of main, so git's
safe delete (`-d`) refuses every time — it would fail on every successful resolve. `-D`
is correct here, and the merge-state check is what makes it provably non-destructive:
if the PR merged, the work is on main, so the branch is genuinely redundant.
**Do not** revert this to `-d`; it will break on every merge.

### Main-safety: stop only on the *dangerous* divergence direction
**Decision:** After merge, `resolve-issue` pulls main when "behind," and stops only when
`git log origin/main..main` (local-ahead) shows commits.
**Why:** A naive check that stops whenever local and origin differ would halt on *every*
merge, because being behind by the just-merged commit always shows a difference. That
would make the safety warning fire constantly and train the user to ignore it —
defeating its purpose. The genuinely dangerous state is local main holding commits
origin lacks (`origin/main..main` non-empty); being behind (`main..origin/main`
non-empty) is the normal, safe, fast-forwardable state. Verified empirically.
**Companion hard rule:** never `git reset` on main to discard commits, in any form.
**Extended (2026-06):** the behind-vs-diverged classification now runs at **every** main
touchpoint, not just resolve time: `prime` reports divergence as a prominent warning,
`start-issue` classifies before its fresh-start pull, and all pulls onto `main` (and
onto issue branches at resume) use `--ff-only` — so a merge commit on main is
mechanically impossible even if a classification step is somehow missed.

### Skills verify the *branch*, not just the issue
**Decision:** `resolve-issue` refuses to run from `main` or detached HEAD and requires an
explicit, working-tree-safe switch to an issue branch. `commit` stops and requires
explicit confirmation before committing on `main` or in detached HEAD. `start-issue`
never commits rescued changes to `main` — a dirty tree on `main` at fresh start is
carried onto the new issue branch via `checkout -b` (which preserves the working tree).
**Why:** The original `resolve-issue` asked "which issue?" when the branch didn't match —
then operated on the *current* branch anyway. Invoked from `main`, that path would
commit and push directly to `origin/main`, shipping unreviewed work around the PR gate:
the only such path in the system, reachable by one wrong answer to an innocuous
question. Likewise `commit`, the only auto-triggerable skill, could create local-main
divergence from a casual "commit this." The fix is one idea applied everywhere: **a
skill must confirm it is standing in the right place before it writes.** The dirty-main
carry exists because "started editing before starting the issue" is the most likely
human mistake in the whole workflow, and `checkout -b` from main is a provably lossless
rescue for it.

### Acceptance criteria must be behavioral, not implementation
**Decision:** `new-issue` writes acceptance criteria as observable conditions checkable
without reading code; mechanisms are explicitly disallowed.
**Why:** Criteria are where "how" tries to sneak past the "what-not-how" principle.
"Results appear within 1 second" is a fine criterion; "uses a debounced input" is
implementation leaking in. Keeping criteria behavioral preserves the core principle
while still giving `resolve-issue` something concrete to verify against.

### `commit` deliberately does NOT cross-check against the issue spec
**Decision:** Drift-detection (does this change match the issue?) lives in
`resolve-issue`, not `commit`.
**Why:** `commit` is the highest-frequency action; its value is being fast and
predictable. Adding issue-fetching and drift-reasoning to every checkpoint commit would
add friction and constant false positives (mid-work commits legitimately touch
not-yet-on-spec scaffolding). Drift is caught once, at resolve time, before it ships.

### `start-issue` checks the working tree *before* any checkout
**Decision:** The in-progress-work safety check runs before resuming or creating any
branch, including before checking out an existing issue branch.
**Why:** An earlier ordering checked out the resume branch first, which could fail or
silently carry uncommitted changes onto the wrong branch — the quiet-data-movement bug
the whole workflow is meant to design out. Protecting the working tree first closes it.

### prime fetches remote state (and stays read-only)
**Decision:** `prime` runs `git fetch --prune` and surfaces behind-count, divergence,
stashes, and open PRs.
**Why:** Without a fetch, prime reports a stale local cache — invisible to collaborators'
pushes and blind to local main being behind. `fetch --prune` updates remote-tracking
refs only; it touches no working files or branches, so it honors prime's read-only
contract.

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
- **`quick`** (fast-path through the rails for trivial fixes): build if micro-task
  overhead actually becomes annoying. A fast path *through* the safety rails, never a
  bypass *around* them — no direct-to-main shortcuts.
- **Hard CI gate** in `resolve-issue`: currently checks report status only; make it
  blocking once GitHub Actions exists to check against.
