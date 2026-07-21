# Contributing

GNADD is a personal project, maintained primarily for my own use and shared
in case it's useful to you. Setting expectations honestly:

- **Issues are welcome.** Bug reports, questions, and ideas — please use the
  issue templates. This project practices what it preaches: GitHub Issues are
  its entire backlog.
- **Unsolicited pull requests may be closed without review.** If you think
  something is worth changing, open an issue first so we can discuss it —
  a PR is the last step of an agreed change, not the first step of a
  conversation.
- **No response-time promises.** I'll get to things when I get to them.

If a change is agreed in an issue, it flows through the GNADD workflow itself
(issue → branch → PR; see [GNADD.md](GNADD.md)): the test suite
(`bash test/run.sh`) must pass, and git mechanics are canonical in
[`bin/gnadd`](bin/gnadd) — never edit the per-skill `gnadd.sh` copies;
`scripts/build.sh` regenerates them.
