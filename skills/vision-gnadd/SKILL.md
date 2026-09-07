---
name: vision-gnadd
description: >-
  Write or revise a project's VISION.md through an interview: the user
  brain-dumps an idea, the agent sorts it by commitment level (Core,
  Possibility space, Open tensions) in the user's own confirmed words, and
  writes the file in the shape GNADD.md defines. Rerunning on an existing
  VISION.md revises it in conversation and preserves what the user does not
  change. Use when the user wants to write a vision, capture the intent behind
  a new project, start VISION.md, or revise the one they have. Never produces
  a plan, roadmap, or spec.
disable-model-invocation: false
---

# Vision

Write `VISION.md` with the user, through conversation. The user talks, the
agent sorts and reflects back, the user confirms, the agent writes. The words
in the file are the user's, whoever typed them. The file's shape is defined in
the canonical guide (`GNADD.md`, "The intent document: VISION.md"). This skill
does not restate the shape. It carries the interview that fills it.

## Auto-Invocation Gate

If this skill was auto-selected from context rather than explicitly invoked
with `/vision-gnadd`, stop before interviewing. Briefly explain why writing or
revising VISION.md appears useful and ask: "Run `/vision-gnadd` now?" Proceed
only after confirmation.

## GNADD Invariants

- VISION.md holds intent, marked by commitment level. Nothing in it has a
  status, an order, or a plan. Those live in issues, PRs, and the phase.
- Nothing enters Core that the user has not confirmed as true no matter what
  gets built.
- The user's words are the words. Reflect them back for confirmation. Never
  paraphrase silently.
- The skill writes the file. It never opens a milestone or an issue. Those go
  through the existing skills, and only on the user's yes.
- For the shape, the admission test, and the rationale, read `GNADD.md`
  (section "The intent document: VISION.md"). It is not bundled with this
  skill. Read it from the repo root when working inside the GNADD repo, or
  fetch it from the pinned URL (pinned to a release by `scripts/release.sh`,
  never hand-edited):

  https://raw.githubusercontent.com/AlexHagemeister/gnadd/v0.5.0/GNADD.md

  For workflow orientation, use `help-gnadd`.

## 1. Check For An Existing File

```bash
test -f VISION.md && cat VISION.md
```

- **Absent:** fresh mode. Go to step 2.
- **Present:** revise mode. Read the whole file. Say what it holds in two or
  three lines (the experience at the center, the invariants by number, how
  many threads the possibility space carries, the open tensions by name).
  Then ask what the user wants to change, or whether they have new material to
  add. Do not start over, and do not re-interview for anything the user does
  not raise. Go to step 3 with only the new or changed material.

## 2. Take The Brain Dump

Ask for the idea as the user would tell a friend, in one go, however long and
however messy. Do not interrupt with questions, do not ask for structure, and
do not ask what matters most. One prompt, then listen.

If the user gives a sentence or two, ask once for more ("Keep going: what
could it become, what would make it great, what are you unsure about?") and
then work with what you have. The grill in step 3 draws out what the dump
lacks. A thin VISION.md that is all the user's is better than a full one
padded by the agent.

## 3. The Grill

The interview borrows its mechanics from Matt Pocock's `grilling` skill and
narrows its aim. Grilling sharpens a plan until the user can commit. This
grill sharpens only Core, and it treats "I don't know" as an answer that
closes a branch rather than a gap to keep digging at. The possibility space
is never grilled.

**Rounds and the frontier.** Model the material as a tree of decisions. The
frontier is every question whose prerequisites are settled: the questions
that can be asked now without guessing at answers not yet heard. Ask the whole
frontier in one round, numbered, each with a recommended answer. Then wait.
Each round's answers push the frontier outward. A question that depends on
another question still open belongs to a later round.

Format a round like so:

```
1. **<question>**
   Recommended: <answer, drawn from the user's words where they exist>

2. **<question>**
   Recommended: <answer>
```

**Recommended answers.** Where the dump already holds the answer, the
recommendation is the user's own sentence, quoted. Where it does not, the
recommendation is marked as the agent's proposal ("my proposal:"). A proposal
never enters the file as written. The user's confirmation or rewording does.

**Facts are the agent's job.** When a question turns on a fact (what the
repo holds, what a tool can do, what the user said in an earlier session
when a connector to their notes is present), look it up. Ask the user only
for decisions.

### The frontier seeds

The shape in `GNADD.md` says what the file needs. These are the questions
that fill it, in the order their prerequisites settle.

**Round 1: the center, and what is Core.**

- What is the experience at the center? One or two sentences, the user's.
- For each claim in the dump, the one sorting question: is this true no
  matter what gets built? Recommended home given for each. Yes goes to Core.
  Anything else stays in the possibility space with no further question. Two
  claims that fight, or a claim the user is unsure of, go to Open tensions.

**Round 2: unlocked by the confirmed invariants.**

- For each invariant: why does it hold? The reason gets attached, and the
  invariants are numbered in the order confirmed.
- What is this deliberately not? Non-goals, in the user's words.
- What does reality impose that the vision bears on? A platform gate, a
  physical limit, a legal line. Only what the vision must respect, never the
  how.

**Round 3: tensions.**

- Where do two possibilities fight? Name each in a sentence and stop. Never
  ask the user to pick a side.
- What do you not know yet? Each "I don't know" is recorded as a tension and
  closes its branch.

The grill is done when the frontier is empty: every claim has a home, every
invariant has a reason, and nothing has been assumed silently.

### Rules that hold across every round

- **The user's words.** Read a claim back in their phrasing with the proposed
  home. When a verb must change to fit its section (a "will" or "should" in
  the possibility space becomes "could", "one direction is", "alternatively"),
  show the changed sentence and ask. Never change wording without reading the
  change back.
- **Do not prune.** Every claim from the dump lands somewhere. Loose,
  contradictory, or half-formed is fine in the possibility space. Group it
  lightly by theme in the user's phrasing and impose nothing more.
- **Do not add.** The agent proposes homes, verb changes, and recommended
  answers. It does not author claims. If the user asks what is missing, answer
  with a question from the seeds, not a sentence for the file.
- **Do not rank.** Never ask whether something is likely, important, or
  first. Those questions manufacture an order the file is not allowed to hold.
- **Catch the how.** A library, a file layout, an architecture, or a step
  sequence in the dump is not a vision claim. Say so and ask what it is for.
  The reason it serves usually is a claim, and that goes in. The how stays
  out.
- **Catch status.** "First", "next", "phase two", "stretch goal", "TBD",
  "done when" describe order or state. Point them at the phase and the
  issues, and leave them out. The content underneath a "TBD" is usually a
  tension, and that goes in.
- **Passivity is a failure.** A round of nothing but "yes" to the agent's
  proposals produces a file the agent wrote. When the user has only agreed
  for a whole round, say so and ask whether the recommendations are their
  view or the path of least resistance.

## 4. Write The File

Write `VISION.md` at the repo root in the shape `GNADD.md` defines: Core,
Possibility space, Open tensions, in that order, with the operating clause in
the file's own words and the possibility-space header stating that nothing in
it is a commitment and that a thread is pulled into an issue when it is time.
Declarative present tense. Never "should" or "will". Plain words for a reader
with zero context.

Before writing, check the draft against the ban list and fix anything that
fails: no library choices, no file layout, no architecture, no task list, no
status, no ordering words, no dates. A line the user confirmed that fails the
list gets read back with the reason, not dropped silently.

Show the whole file and ask the user to read it. Take corrections in their
words. Write again until they say it is right.

**Revise mode:** change only the lines the user changed or added. Every other
line stays byte for byte. When a change touches Core, say so, and name how it
lands per the guide's open question on Core routing (an issue and PR, or a
direct commit): pick one, and say which.

## 5. How The File Lands

The skill writes the file to the working tree and reports the path. It does
not commit. Say plainly that the file is unstaged, and that on a
rails-protected `main` the honest route is a branch and PR (`/quickfix-gnadd`
fits a fresh VISION.md: the guard exempts a newly added `VISION.md` from its
line budget, so the file lands without an override. A Core revision on an
existing project goes back under the budget and may deserve an issue, per
the open question above). The commit is the user's act.

## 6. The Closing Offer

Ask two questions, one at a time, and act on neither without a yes:

1. **Open the first phase?** If yes, ask what the phase is trying to find out
   and what ends it, in the user's words, and run:

   ```bash
   bash "<prime-gnadd skill-dir>/gnadd.sh" phase open "<title>" --description "<what it is trying to find out, and what ends it>"
   ```

   (`prime-gnadd` bundles the script. This skill does not.) Skip the question
   when a phase is already open.

2. **Capture the first issue?** If yes, hand off to `/new-issue-gnadd`. Its
   interview mines this conversation, cites the invariant the issue serves,
   and attaches to the open phase. Do not draft the issue here.

A "no" to either is complete. Do not nudge again.

## Closing Guidance

Report in three lines: the file's path and whether it is new or revised, how
many invariants Core holds and how many tensions are named, and what the user
said yes or no to in the closing offer. No plan, no next steps beyond that.
