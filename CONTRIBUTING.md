# Contributing

GNADD is a personal project that other people have started using. Issues and
pull requests from outside are welcome, on the terms below.

## What is welcome

- **Issues.** Bug reports, questions, and ideas. Use the issue templates. The
  tracker is also this project's own backlog (GNADD practices what it
  preaches: GitHub Issues are its entire task list), so expect to see the
  maintainer's work items alongside yours.
- **Small pull requests** for things that need no discussion: a typo, a broken
  link, a wrong command.
- **Larger changes, after an issue.** Open an issue first and wait for a yes
  before building. That lets the maintainer say no to the idea before anyone
  spends time on the code. A PR for a non-trivial change with no issue behind
  it may be closed with a request to open one.
- **Security reports**, always, through the private channel in
  [SECURITY.md](SECURITY.md). Never a public issue.

## How to send a change

1. Fork the repo and branch off `main`.
2. Make the change. Skill behavior lives in `skills/<name>/SKILL.md`. Git
   mechanics live in [`bin/gnadd`](bin/gnadd) only: never edit the per-skill
   `gnadd.sh` copies, run `scripts/build.sh` to regenerate them.
3. Run `bash test/run.sh`. It must pass, and it fails if the copies drift.
4. Open a pull request against `main`. Say what the change does and why, and
   name the issue it resolves if there is one.

The maintainer works the same loop (issue, branch, PR, see
[GNADD.md](GNADD.md)), so your PR lands the same way theirs do: green CI, a
human reads the diff, one squash commit on `main`.

## The maintainer's terms

- **Every diff gets read before it merges.** CI passing is necessary, not
  sufficient.
- **A first PR waits for approval before CI runs.** That is a GitHub default
  for first-time contributors and it stays on.
- **No response-time promises.** This is a side project. Issues and PRs get
  attention when the maintainer has it.
- **No is a normal answer.** GNADD is opinionated on purpose. A change that
  fits your workflow but not the model here may be declined, with the reason.
  Forking is the sanctioned way to keep a change the upstream does not want
  (the README's Quickstart, route 3, covers installing from a fork).
