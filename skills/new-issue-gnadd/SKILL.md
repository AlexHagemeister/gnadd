---
name: new-issue-gnadd
description: Draft GitHub issues from natural language descriptions. Use when the user describes new work, asks to capture a backlog item, or needs a behavior-focused GitHub issue; interviews for requirements as needed, confirms the draft, and creates the issue via GitHub CLI after approval.
disable-model-invocation: false
---

# New Issue

Write GitHub issues from natural language descriptions. After the user approves the draft, create the issue with `gh`.

## Auto-Invocation Gate

If this skill was auto-selected from context rather than explicitly invoked with `/new-issue-gnadd`, stop before interviewing or drafting. Briefly explain why capturing a GitHub issue appears useful and ask: "Run `/new-issue-gnadd` now?" Proceed only after confirmation.

## GNADD Invariants

- Issues are the backlog and the working spec; do not create or update markdown task lists as a substitute.
- Capture intent as observable behavior: what changes, why it matters, and what proves it is done.
- Prefer thin vertical slices over broad plans or horizontal implementation layers.
- For broader workflow or file-hygiene guidance, use `help-gnadd`.

## Creation Mode

Finalize approved drafts with GitHub CLI:

- Show the issue draft for review before creation.
- Accept user edits to title, body, scope, criteria, and label.
- Ask whether to create the approved issue with `gh`.
- Do not create an issue until the user approves the draft and confirms creation.

## Workflow

1. **Assess** — Inventory what is already known from the invocation and conversation.
2. **Extract** — Interview the user for anything still missing (see below). Do not draft until extraction is complete.
3. **Draft** — Structure the resolved details into the issue format.
4. **Review** — Present the draft; get approval and creation confirmation.
5. **Finalize** — Create the issue via `gh`.

## Extraction

Interview the user relentlessly until every detail needed for a quality, actionable issue is resolved and you reach shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one-by-one.

### Entry mode

- **Mid-conversation:** `/new-issue-gnadd` during an existing discussion. Mine the conversation for problem, outcome, scope, and criteria. Do not ask the user to re-describe what was just discussed. Interview only for **outstanding gaps** — ambiguities, missing boundaries, unstated acceptance conditions, or unresolved scope forks. If the user adds a scoping note, use it to narrow the issue.
- **Cold start:** `/new-issue-gnadd` with little or no context (e.g. a fresh chat). Run a **full extraction interview** from scratch. Treat a brief description as a starting point, not a complete spec.

### What must be resolved

Before drafting, have enough to write every required section confidently:

| Detail | Resolve by asking… |
|--------|-------------------|
| Problem / Motivation | What is wrong or missing today? Who is affected? What triggered this? |
| Desired Outcome | What does "done" look like behaviorally? What should users or the system do differently? |
| Acceptance Criteria | What observable conditions prove done? What edge cases matter? |
| Scope | Is this a vertical slice or part of something larger? What is explicitly out of scope? |
| Constraints | Any hard boundaries (deps, perf, compatibility, rollout)? |
| Subtasks | Does this decompose into distinct behavioral slices, or is it one thin slice? |

Optional **Context** can be inferred from the repo or conversation; do not interview for it unless ambiguity would block a good issue.

### Interview rules

- **One question at a time.** Do not batch questions.
- **Provide a recommended answer** with each question so the user can confirm, correct, or pick quickly.
- **Explore the codebase** when a question can be answered there — do not ask what you can verify yourself.
- **Stay behavioral.** Ask about what and why, not how. Redirect implementation talk into observable outcomes.
- **Resolve dependencies in order.** Finish one decision branch before opening the next; do not leave scope forks unresolved.
- **Stop when ready.** Move to drafting once you can write concrete acceptance criteria without guessing. For single-action fixes (e.g. a typo), a short interview may suffice.
- **Flag scope creep.** If the emerging spec looks like multiple independent issues bundled together, pause and call it out before continuing (see Scope creep below).

## Core Principle

Issues describe **what** and **why**, never **how**.

- Write behavioral specs, not implementation recipes.
- Describe observable user-facing or system-facing behavior.
- Distill implementation details into behavioral intent.
- Do not include framework-specific instructions, code patterns, file paths to edit, or architecture decisions in the issue body.
- Exception: the optional **Context** section may reference existing issues, docs, endpoints, or repo state as orientation, but not as instructions.

## Scope

Prefer vertical slices: each issue should deliver a thin end-to-end behavior that can be built, tested, and verified in isolation.

- Good: "Users can search by keyword and see matching results."
- Bad: "Build the data access layer for search."
- If subtasks are needed, keep each subtask behavioral and vertical where possible.
- Omit subtasks for single-action fixes.

### Scope creep

Watch for scope creep during extraction, drafting, and review. A single issue should be one thin vertical slice — not several unrelated slices disguised as subtasks.

**Signals to flag:**

- Multiple independent problems or user journeys that do not need to ship together
- Acceptance criteria that cluster into separate, unrelated behavioral areas
- Subtasks that could each be their own buildable, verifiable issue
- Frequent "and also" / "while we're at it" additions during the interview
- The title or desired outcome cannot be stated in one specific sentence without "and"

**When flagged, tell the user explicitly.** Do not silently absorb extra scope. Example tone:

> This looks like three separate issues bundled together. Consider splitting into:
> - **A:** \<title\> — \<one-line behavioral summary\>
> - **B:** \<title\> — \<one-line behavioral summary\>
> - **C:** \<title\> — \<one-line behavioral summary\>
>
> Which slice should this issue cover? The rest can become separate issues.

Ask the user to pick one slice for *this* issue (or confirm they intentionally want a larger umbrella issue). Move unrelated work to **Constraints / Non-goals** or defer to separate issues — do not pack them in as subtasks unless they truly must ship in the same change.

## Draft Structure

Extract or infer:

- **Title:** Concise, specific summary. Good: "Navbar shows stale user data after profile update". Bad: "Fix navbar bug".
- **Problem / Motivation:** What is wrong or missing, at the level of observable behavior. Avoid implementation details.
- **Desired Outcome:** What done looks like, at the behavioral level. Describe the target state, not steps.
- **Acceptance Criteria:** A checkable list of observable conditions that define "done." See the rules below. Include by default; omit only for genuinely single-action fixes (e.g. a typo) where the title already says everything.
- **Subtasks:** Include only when the work naturally decomposes into distinct behavioral slices.
- **Constraints / Non-goals:** Optional. Include only when there is a real boundary worth recording — a hard limit that is part of "what done means," or something explicitly out of scope. Omit when there is nothing meaningful to say.
- **Context:** Include only when non-obvious conversation or repo context would help a future session. Reference existing artifacts by path, issue number, or URL instead of duplicating them.

### Acceptance Criteria rules

Acceptance criteria are the positive spec: the observable conditions that, if all true, mean the issue is done. A future implementer checks finished work against them, so they must be **verifiable by observing behavior, not by reading code**.

- Each criterion is something a reviewer could confirm by using the software, not by inspecting the implementation.
- Phrase as checkable statements. Good: "Searching an empty string returns all rows." / "Submitting an invalid email shows an inline error and does not save." Bad (implementation leaking in): "Uses a debounced input." / "Calls the `/search` endpoint." / "Adds an index to the users table."
- A measurable performance or boundary condition *is* behavioral and allowed ("results appear within 1 second"); the **mechanism** that achieves it is not.
- Keep them minimal and genuinely necessary — 2–5 for most issues. If you cannot state a criterion without naming a function, file, or library, it belongs in implementation conversation, not the issue.

### Constraints / Non-goals rules

Use this section for the *negative* spec — boundaries that shape what counts as done without dictating how:

- Hard constraints that are part of the spec: "Must not add new runtime dependencies." / "Must work without network access."
- Explicit non-goals to prevent scope creep: "Out of scope: pagination — results can be unbounded for now."
- This is distinct from **Context** (which is orientation, not a boundary). Like acceptance criteria, state boundaries behaviorally, not as implementation directives.

## Label

Suggest exactly one label, e.g. `bug`, `enhancement`, `chore`, etc. Choose based on the issue intent, then present it with the draft for user confirmation or override.

## Review Gate

Before finalizing, show the user:

```markdown
Title: <title>
Label: <bug|feature|chore>

## Problem / Motivation
<observable problem or missing behavior>

## Desired Outcome
<behavioral target state>

## Acceptance Criteria
- [ ] <observable, checkable condition>
- [ ] <observable, checkable condition>

## Subtasks
- <behavioral subtask>

## Constraints / Non-goals
<only if a real boundary exists>

## Context
<only if useful>
```

Omit empty optional sections (Subtasks, Constraints / Non-goals, Context). Acceptance Criteria should be present for all but single-action fixes. If the draft still looks like multiple issues in one, flag scope creep again before asking for approval. Accept user edits to title, body, scope, criteria, and label.

Ask whether to create the approved issue with `gh`.

## Finalize

After approval and creation confirmation, create the issue via `gh`.

1. Ensure the selected label exists — create it **only if missing** (`gh label create` errors on an existing label):
  ```bash
   gh label list --search "<label>" --json name --jq '.[].name' | grep -qx "<label>" \
     || gh label create "<label>"
  ```
2. Create the issue:
  ```bash
   gh issue create --title "<title>" --body "<body>" --label "<label>"
  ```

Use the current repository unless the user specifies another repo.

## Report Back

Confirm with the issue number and URL.

## Closing Guidance

Offer a brief next-step nudge only after finalization — not during extraction, at the review gate, or while awaiting creation confirmation.

Nudge toward `/start-issue-gnadd <N>` as the primary next step. If the user was capturing side work mid-session, offer returning to that work as an alternative.

Keep it to a sentence or two with invitational options.