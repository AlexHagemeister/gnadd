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
- For the shape, the admission test, and the rationale, read `GNADD.md`. For
  workflow orientation, use `help-gnadd`.

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
then work with what you have. A thin VISION.md that is all the user's is
better than a full one padded by the agent.

## 3. Sort By Commitment

Take the dump apart into claims, keeping each in the user's phrasing. For each
claim there is one sorting question, and it is the only question the interview
asks per item:

> Is this true no matter what gets built?

- **Yes** goes to Core. Ask for the reason it holds ("why is this
  non-negotiable?") and attach it. Number the invariants in the order the user
  confirms them.
- **Anything else** stays in the possibility space. No follow-up question. Do
  not ask whether it is likely, important, or first. Those questions
  manufacture an order the file is not allowed to hold.
- **Two claims that fight**, or a claim the user says they do not know about
  yet, go to Open tensions. Name the tension in a sentence. Do not ask the
  user to resolve it.

Conduct the sort as a reflection, not a quiz. Read a claim back in the user's
words with your proposed home ("Core: 'it works offline'. True no matter
what?") and let them confirm, move it, or reword it. Batch the possibility
space into a few short reads rather than one item at a time. Core items get
confirmed one by one.

Rules for the sort:

- **The user's words.** When a claim needs a verb changed to fit its section
  (a "will" or "should" in the possibility space becomes "could", "one
  direction is", "alternatively"), show the changed sentence and ask. Never
  change wording without reading the change back.
- **Do not prune.** Every claim from the dump lands somewhere. Loose,
  contradictory, or half-formed is fine in the possibility space. That
  section holds the creative material and the interview does not impose
  structure on it beyond light grouping by theme, in the user's phrasing.
- **Do not add.** The agent proposes homes and verb changes. It does not
  propose claims. If the user asks what is missing, answer with a question,
  not a sentence for the file.
- **Catch the how.** A library, a file layout, an architecture, or a step
  sequence in the dump is not a vision claim. Say so and ask what it is for.
  The reason it serves usually is a claim, and that goes in. The how stays
  out.
- **Catch status.** "First", "next", "phase two", "done when" describe order
  or state. Point them at the phase and the issues, and leave them out.
- **Stop when the dump is sorted.** Do not go looking for more material.

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
fits a fresh VISION.md; a Core revision on an existing project may deserve an
issue, per the open question above). The commit is the user's act.

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
