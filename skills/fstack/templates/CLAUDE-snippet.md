<!--
Block to paste at the end of the project's CLAUDE.md (or AGENTS.md).
Create the file if it does not exist. Adapt the paths if the project uses others.
Keep it short: CLAUDE.md is loaded every session, it is the most expensive surface.
-->

## Context convention

This project is documented so that a cold restart never costs information. The repository is
the source of truth, not the conversation.

**Read at the start of a session, in this order**

1. `TODOS.md`, the "Resume state" block first, and nothing else in the file. It is the anchor.
2. `CODEMAP.md`, its outline then the useful section, to locate what you will touch. If the
   zone concerned has its own map, read that one.
3. `CHANGELOG.md`, only the last 2 or 3 entries.
4. The `docs/` pages of the modules the task concerns only. `docs/README.md` is the index.
   `docs/decisions/` holds the choices already made and their why.

**Never read `archives/` on resume.** It is false or cold content by construction, kept for
history. To search it, go through the `fstack` skill: its brief mode resolves the path of the
search script, which returns the provenance with the excerpt without loading the files. A bare
grep returns the line without its header.

**At the end of a session, before any cold restart**: run `/fstack:debrief`, or simply ask to
tidy the project. It resyncs the 3 pillars, updates the `docs/` pages of the modules touched,
moves to `archives/` everything that became false, and puts each file back in its budget.

**The rules that hold it together**

- No silent deletion. What is obsolete goes in `archives/`, with its reason.
- No known-false claim left in the docs or in the pillars.
- A durable rule that became false is deleted right away, not archived.
- One piece of knowledge has one owner: a decision in an ADR, a pitfall in the module page or
  the map of its zone, a durable preference here, an environment constraint in the CODEMAP.
- No work in progress without a task written in `TODOS.md`.
- Each surface has a budget. This file aims at 100 lines and carries neither state nor story,
  the resume block fits in 40 lines, the CHANGELOG rotates. True but too long docs are lost docs.
- Never a secret in a tracked file. Say where the key is, not what it is worth.

**Writing style**: direct tone. No em dash, no semicolon, no phrasing that smells generated.
The full rule is in the `style-redaction` skill, to load before writing a document.

<!-- fstack:orchestration -->
## Orchestration

- The main session orchestrates and keeps the judgment: framing, arbitration, irreversible decision, validation.
- Each task goes to the cheapest `fstack:<profile>` that meets its done criterion.
- The detail is in the `DELEGATION.md` reference of the `fstack` skill.
