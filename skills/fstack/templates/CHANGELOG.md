# CHANGELOG, {{PROJECT_NAME}}

> What changed, why, and how to go back.
> Most recent on top. One entry per useful session, not one per commit. Append-only: the past
> is not rewritten, it is corrected by a new entry.

<!-- An entry fits in 25 lines, the detail goes in a docs/ page and the entry points to it.
     Beyond 30 entries, the log rotates: the old ones go to
     archives/changelog/YYYY-MM.md through ctx-rotation.sh, which leaves here the line saying so. -->

---

## {{DATE}}, context convention set up

**What**: added `CODEMAP.md`, `TODOS.md`, `CHANGELOG.md`, `docs/`, `archives/`.

**Why**: to restart from an empty context without losing information. The repository becomes the
source of truth.

**Rollback**: delete the added files. No impact on the code.

**See also**: `docs/README.md`, `archives/README.md`.
