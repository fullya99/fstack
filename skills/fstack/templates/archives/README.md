# Archives, {{PROJECT_NAME}}

> ⚠️ **Nothing here is a source of truth.** This directory keeps two things, what was true
> and no longer is, and what is still true but cold, the old log entries set aside by rotation.
> The header of each file says which of the two it is. Nothing here is read on session resume,
> nothing is cited from a living page. Only on explicit archaeology request.
>
> Up-to-date documentation is in `docs/` and in the 3 pillars at the root.

## Rules

**No silent deletion.** A removed document is moved here, never erased.

**Location**: `archives/<YYYY-MM>/<full original path>`. The dated bucket avoids collisions over
time, the preserved path makes provenance readable.

**Move with `git mv`**, to keep the file history.

**Mandatory header** at the top of the archived file:

```markdown
> ⚠️ **ARCHIVED on YYYY-MM-DD**, unmaintained, kept for history.
> **Origin**: `<original path>`
> **Reason**: <explicit and verifiable, not just "obsolete">
> **Replaced by**: `<path>` (or "none, the subject no longer exists")
> **Not a source of truth.**
```

Paths are written from the repository root, never as a relative link. A moved file breaks its
relative links.

**Do not go here**: dead code (git keeps it), builds and caches, secrets even expired, drafts
never published, durable rules that became false (deleted), superseded ADRs (they stay in
place, marked).

## Searching it

```bash
bash "$SKILL/scripts/ctx-archaeology.sh" <pattern>          # provenance and excerpts, bounded output
bash "$SKILL/scripts/ctx-archaeology.sh" --list          # inventory, one entry per file
```

Not a bare `grep`: it returns a line without its header, so a cold entry gets taken for a
current truth.

## Index

| Archived on | Origin | Location | Reason | Replaced by |
|---|---|---|---|---|
| | | | | |

<!-- Most recent on top. A line added in the same move as the move itself.
     A file present in archives/ but absent from this index is a defect. -->
