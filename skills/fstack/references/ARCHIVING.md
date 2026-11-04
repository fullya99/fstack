# ARCHIVING: the rule that keeps docs clean

> Docs do not rot because too little was written. They rot because falsehood is left alive next to
> truth. `archives/` exists so you can remove without hesitating. Obsolete content is moved, never
> destroyed, so archiving costs nothing.

## The two invariants

**No silent deletion.** What mattered has the right to be found again, with the date and the reason
it was set aside.

**`archives/` is never a source of truth.** This means two things: never read on resume, never cited
from a live page. It is not used to answer a question about the current state, only on an explicit
archaeology request. `ctx-audit.sh` now sees both cases.

The two rules hold each other up. Because nothing there is ever read, you can throw into it
generously.

---

## Decision tree

Apply to any suspect content: page, procedure, script, plan, proposal, lasting rule.

```
Is the content false, stale or replaced?
├── NO → touch nothing.
└── YES
    ├── Is it a whole FILE that became useless or false?
    │   ├── YES → ARCHIVE, see "The move, in one command". The criterion is about incoming
    │   │         references: for each reference to the file, is it operative, someone needs it
    │   │         to act now, or historical, a comment telling the provenance? Archive when all
    │   │         remaining references are historical. Testable with a `git grep`, unlike
    │   │         "false, stale or replaced", which stays a judgment.
    │   └── NO → it is a SECTION of a file still useful
    │             → FIX IN PLACE, note it in the CHANGELOG.
    │               Do not archive a live file for one false section.
    ├── Is it a LASTING RULE (CLAUDE.md entry)?
    │   └── → DELETE. No archiving.
    │         A false rule is worse than none. Its trace goes to the CHANGELOG if useful.
    ├── Is it a superseded ADR?
    │   └── → STAYS IN PLACE, status "Superseded by ADR-00NN".
    │         The only exception to archiving, an ADR is worth its historicity.
    ├── Is it a TASK done or abandoned (TODOS.md)?
    │   └── → DELETE from TODOS. The accomplished fact lives in the CHANGELOG.
    ├── Is it a log ENTRY, true but old?
    │   └── → ROTATION, never rewritten or summarised. See below.
    └── Is it a dead REFERENCE (link, path, deleted resource)?
        └── → FIX if a replacement exists, otherwise REMOVE and say so.
```

What you never do: leave a `TODO: this section is false` in a live doc, keep "just in case",
comment instead of moving, delete a documentation file without a trace.

---

## The move, in one command

Two steps, never one.

```bash
bash "$SKILL/scripts/ctx-archive.sh" --verify <path>
bash "$SKILL/scripts/ctx-archive.sh" <path> --reason "..." --replaced-by "..."
```

`--dry-run` announces without writing. `--force` overrides a live link, take it only knowingly.

The first call writes nothing, it classifies incoming references and says whether a live markdown
link blocks archiving. The second does everything, in order.

1. It reclassifies incoming references and refuses if a live markdown link to the file remains,
   that link would break on the move.
2. It moves with `git mv`, the file's history stays tracked.
3. It adds the provenance header.
4. It resolves the moved file's relative links, from the repo root. The original path is
   re-injected under the archive prefix, the depth changes, going up with `../` is not enough, you
   must come back down from the root.
5. It adds the index line in `archives/README.md`.
6. It checks with `git grep` that no occurrence of the old path remains outside the archives, and
   exits with an error otherwise.

This last step is the gate that was missing. The manual move had four steps, and the fourth, the
index line, was skipped most often, with nothing to flag it.

Variant `--summary <file>`: the file keeps its place as a summary, the full text goes to the
archive. `<file>` is put at the old path, and `{{ARCHIVE}}` in it becomes the archive path. Incoming
references stay valid, so they do not block, and the final check verifies the summary is in place.
This is the call made by `ctx-rotation.sh --plans`.

The script refuses to archive a pillar (`CODEMAP.md`, `TODOS.md`, `CHANGELOG.md`, `CLAUDE.md`) and
an index (`docs/README.md`, `archives/README.md`). A false section of a pillar is fixed in place, a
lasting rule that became false is deleted, see the decision tree.

---

## Where the archived file goes

```
archives/<YYYY-MM>/<full original path>
```

| Origin | Destination |
|---|---|
| `docs/modules/auth-legacy.md` | `archives/2026-08/docs/modules/auth-legacy.md` |
| `scripts/deploy-v1.sh` | `archives/2026-08/scripts/deploy-v1.sh` |
| `docs/ops/migration-mongo.md` | `archives/2026-08/docs/ops/migration-mongo.md` |
| `CHANGELOG.md`, August entries | `archives/changelog/2026-08.md` (rotation, not `git mv`) |

Why this scheme. The dated bucket avoids collisions when the same path is archived several times
over the project's life. The preserved original path makes provenance readable without opening the
file.

Always use `git mv`, not a copy followed by a delete. The file's history stays tracked.

---

## Archive header, required

Inserted at the very top of the moved file, before its title.

```markdown
> ⚠️ **ARCHIVED on 2026-08-13**, unmaintained, kept for history.
> **Origin**: `docs/modules/auth-legacy.md`
> **Reason**: the cookie session flow was replaced by OAuth. The procedure described
> no longer works since the 2026-08-13 overhaul.
> **Replaced by**: `docs/modules/auth.md` (or "none, the subject no longer exists")
> **Not a source of truth.**
```

The French header of an older archive (`ARCHIVE le`, `Origine`, `Raison`, `Remplace par`) is also
read.

Three form rules.

Paths are written from the repo root, in `code`, never as a relative link. A moved file breaks all
its relative links, and a dead link in an archive is one more pitfall.

The reason is explicit and verifiable. "Obsolete" informs nobody. "Replaced by X following the
<date> overhaul" lets you decide whether the archive still has any interest.

If the page is archived without a replacement, say so. It is information in itself.

---

## The `archives/README.md` index

Without an index, `archives/` becomes a junk room nobody searches, and archived content is lost for
good. You might as well have deleted it.

```markdown
| Archived on | Origin | Location | Reason | Replaced by |
|---|---|---|---|---|
| 2026-08-13 | `docs/modules/auth-legacy.md` | `archives/2026-08/docs/modules/auth-legacy.md` | replaced by OAuth | `docs/modules/auth.md` |
```

The French index of an older project (`Archivé le`, `Origine`, `Emplacement`, `Raison`,
`Remplacé par`) is also read.

Most recent on top. One line per item, added in the same move as the relocation. A file present in
`archives/` but absent from the index is a defect, `ctx-audit.sh` reports it.

---

## Cold history, log rotation

An old CHANGELOG entry is not false, it is cold. `archives/` is the only place the convention never
reads on resume, which is exactly the property we want for content that is true but no longer helps
decide.

`$SKILL/scripts/ctx-rotation.sh` keeps a log's 30 most recent entries and moves the others to
`archives/<log>/YYYY-MM.md`, grouped by the entry's month. One `ARCHIVED` header per month file
created, never per entry. One index line in `archives/README.md` per file created. Run it with
`--dry-run` first, it is idempotent.

A rotation header reads:

```markdown
> ⚠️ **ARCHIVED**, entries of `CHANGELOG.md` moved by rotation on 2026-08-13, kept for history.
> **Origin**: `CHANGELOG.md`
> **Month**: 2026-07
> **Not a source of truth.** Current state lives in the root pillars.
```

The French form (`ARCHIVÉ`, `Mois`) is also read.

It recognises the three formats of the `journal:` key of the convention block: `date-titre`
(`## YYYY-MM-DD`), `keep-a-changelog` (`## [x.y.z] - YYYY-MM-DD`) and `crochets`
(`[YYYY-MM-DD] [TYPE] text`, one line per entry or one line followed by its body). Without a
declaration, it detects the format and says so. It applies to any log of these formats, not only
`CHANGELOG.md`.

Two safeguards. A log sorted from oldest to newest is refused, code 3, because rotation would keep
the oldest entries and archive the most recent. A month that would exceed 1,500 lines is cut into
`YYYY-MM.md`, `YYYY-MM-2.md`, and so on, the oldest in the lowest rank, each file indexed. `--cap`
sets this limit.

No `git mv` here, it is a content split inside a file, the only exception to this page's `git mv`
rule.

### Executed plans

`ctx-rotation.sh --plans [--root <path>] [--dry-run]` handles `plans/*.md`. A plan is executed when
one of these marks exists: a `Status: finished` line (or the `PLAN EXECUTED` banner) in its first 30
lines, without negation, or a `TODOS.md` line that cites `plans/<name>.md` with "done", "executed"
or a checked box. An executed plan of more than 20 lines becomes a summary of at most 20 lines at
its original path: title, goal, deviation log, commits. The full text goes to
`archives/YYYY-MM/plans/<name>.md` through `ctx-archive.sh --summary`, with its header and index
line. The path does not change, incoming references stay valid. A plan already summarised (marker
`plan-resume`) or of 20 lines or fewer is not touched. The full text keeps everything, including
boxes left open.

The summary uses `**Goal.**` and a `## Deviation log` section. The French `Objectif` and
`Registre des écarts` are also read.

---

## What does not belong in `archives/`

`archives/` documents the history of the project's knowledge, not its waste.

- ❌ dead code, git already keeps it, delete it and that is all,
- ❌ dependencies, builds, caches, bulky exports, that is not documentation,
- ❌ secrets even expired, they are revoked, not archived,
- ❌ drafts never published, they never held authority, there is nothing to trace,
- ❌ lasting rules that became false, see the decision tree.

Simple rule: archive what was considered true and no longer is. Log rotation is the second case,
and the only one, where `archives/` receives true content. The header says which of the two a file
is, because a reader doing archaeology should not have to guess.

---

## Going back, without loading everything

`archives/` is never read by default. If there is no explicit path into this directory, the
no-read-on-resume prohibition amounts to losing what we claim to keep.

```bash
bash "$SKILL/scripts/ctx-archaeology.sh" <pattern>            # searches, returns provenance then excerpts
bash "$SKILL/scripts/ctx-archaeology.sh" --list               # inventory of what is archived
bash "$SKILL/scripts/ctx-archaeology.sh" --file <path>        # provenance of one specific archive
```

It always returns provenance BEFORE the excerpt, never the reverse, so an archive is not taken for
a current truth. It tells cold from false: a rotation entry was true at its date, a file archived by
`ctx-archive.sh` stopped being true. Output is bounded by `--max`, 20 occurrences by default.

Why not a bare `grep` on `archives/`. It returns a line without its header, so cold gets mistaken
for current without anyone knowing. And on a log archive of several thousand lines, it dumps more
than it returns.

---

## Purging archives

Archives are re-read about once a year, or when the directory becomes large.

An archive nothing depends on, whose subject has entirely disappeared, can be deleted for good. Git
keeps the history, and the deletion's commit message plays the role of the destruction certificate
expected in records management, it says what, when and why.

The matching index line stays, with the note `deleted on YYYY-MM-DD`. The index is the only thing
never purged.

No automatic purge. It is an explicit decision, never a side effect of a debrief.
