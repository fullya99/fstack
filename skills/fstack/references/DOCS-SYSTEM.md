# DOCS-SYSTEM: how `docs/` is organised

> `docs/` is the only zone where long-form knowledge may live. Its value rests on a single
> property: **everything in it is true**. As soon as a stale page is tolerated, the reader must
> recheck everything, and the whole zone loses its point.

## Tree

```
docs/
├── README.md              # index, the only entry door
├── modules/               # how a technical building block works
│   └── <module>.md
├── features/              # how a user-facing capability works
│   └── <feature>.md
├── ops/                   # replayable procedures (setup, deploy, migration, incident)
│   └── <procedure>.md
├── pitfalls/              # pitfalls with no module, a numbered registry
│   └── README.md
└── decisions/             # ADRs, why we decided this way
    └── ADR-0001-<slug>.md
```

The four subdirectories are not decorative, they match four different questions. A page that
hesitates between two is often two pages. The directory `docs/pieges/` of an older project is read
like `docs/pitfalls/`.

| Directory | Question | Goes stale when |
|---|---|---|
| `modules/` | How does this building block work? | the code changes |
| `features/` | What does the product do, end to end? | the behaviour changes |
| `ops/` | How do I redo this operation? | the tooling or infra changes |
| `decisions/` | Why this choice? | never, we supersede instead of rewriting |

On a small project, `modules/` and `features/` can stay flat in `docs/`. Create the structure when
the volume justifies it, do not anticipate it.

---

## What deserves a page

Documenting everything does as much damage as documenting nothing. Noise makes the true unreadable,
and a page nobody maintains ends up lying.

**A page is justified if at least one of these holds:**

- several files cooperate to deliver the service, and the logic is readable in none of them,
- an API or contract is consumed elsewhere in the project,
- there is a non-obvious invariant in the code, such as "call order matters" or "this cache must
  be invalidated first",
- it was hard to get working, and what cost time once will cost it twice,
- an operation must be replayable by someone else, or by you in six months,
- a structuring decision was made among several credible options.

**A page is not justified** if the code is self-explanatory, if the content paraphrases the
signatures, if the building block is trivial or disposable, or if the information already has its
place in a pillar.

The deciding test: would removing this page cost someone time? If not, it does not need to exist.

---

## Status header, required

Every page starts with this block. It lets a reader, human or agent, know in one line whether the
content can be trusted. And it is what `ctx-audit.sh` reads to detect drifting pages.

```markdown
> **Status**: ✅ up to date, verified on 2026-08-13 against `src/auth/session.ts`, commit `a1b2c3d`
> **Type**: module
> **Scope**: `src/auth/**`, `src/middleware/session.ts`
> **See also**: `docs/features/login.md`, `docs/decisions/ADR-0003-sessions.md`
```

The French header of an older project (`Statut`, `Portée`) is also read.

| Status | Meaning | Next |
|---|---|---|
| `✅ up to date` | verified against the code at the stated date | nothing to do |
| `🟡 to verify` | the scope moved, the page was not re-read | handle at the next debrief |
| `🔴 obsolete` | false content or vanished subject | moves to `archives/`, at the current debrief |

The status is dated and sourced. The date says when, the source says against what: a file, a
commit, a replayed command, a documentation page with its consultation date. A status without a
source is only a declaration, and "verified" with no object is worth nothing.

A `🔴` does not survive a debrief. A `🟡` that lingers over two debriefs is either verified or
archived, not left hanging.

The `Scope` field lists the paths the page describes. It makes maintenance mechanical. When the
session touches `src/auth/`, you know at once which pages to re-read.

---

## The `docs/README.md` index

An unindexed page is an invisible page. Nobody reads it, so nobody corrects it. The index is
updated in the same move as the page.

```markdown
| Page | Type | Scope | Status | Verified on |
|---|---|---|---|---|
| [auth](modules/auth.md) | module | `src/auth/**` | ✅ | 2026-08-13 |
| [login](features/login.md) | feature | login flow | 🟡 | 2026-06-02 |
```

The index also carries a "Recently archived" section pointing to `archives/README.md`. A reader
looking for a vanished page must find where it went without digging.

---

## Writing a page

Start with the conclusion. A reader who stops after three lines must already have the essentials.

Stay short. A big document is never updated, so it lies. Target 200 lines, warning at 250, blocker
at 300, measured by `ctx-audit.sh --budget`.

A module page that swells with pitfalls is often a zone that ignores itself. When the module has a
directory, its pitfalls go in `<zone>/CODEMAP.md`, and the page keeps the how and the why. See
`references/ZONES.md`.

Do not paraphrase the code. The code says what, the page says why, how it fits together, and what
breaks if you touch it.

On an already long page, a heading depth beyond four levels usually signals several subjects, a
GitLab style rule. `ctx-audit.sh` reports it.

Cite real, clickable paths such as `src/auth/session.ts:42`, not vague descriptions.

Put pitfalls before details, each marked 🪤 at the start of the line. The marker is what
`ctx-audit.sh` counts and attaches to an owner, see below.

Put details after. The "good to know" section saves more time than the exhaustive description.

No secrets. Say where a key is, never its value.

Templates are in `templates/docs/`: `module.md`, `feature.md`, `procedure.md`, `ADR.md`.

---

## Pitfalls, one owner each

A pitfall is what cost time once and will again. It is marked 🪤 and lives with a single owner.

| The pitfall concerns | It lives in |
|---|---|
| a module | the page `docs/modules/<module>.md` |
| a zone | the map `<zone>/CODEMAP.md` |
| nothing identifiable, or the whole project | `docs/pitfalls/` if the project has one, otherwise the sensitive zones section of `CODEMAP.md`, never both in one project |

`docs/pitfalls/README.md` holds the numbered registry, one number per pitfall, monotonic, never
reused, like ADRs.

```markdown
| No. | Pitfall | Symptom | Workaround | Status |
|---|---|---|---|---|
| P-003 | 🪤 the cache survives a restart | yesterday's data served | purge `var/cache` before the test | active |
```

A pitfall fixed at the source becomes `resolved on <date>` in the registry, it does not disappear.
A pitfall left in `TODOS.md` is lost with the resume block, the audit reports it. `CLAUDE.md` is
not a pitfall owner, except for a conduct rule that holds for the whole project.

---

## ADRs, decisions

An ADR captures a structuring decision: context, options considered, chosen option, consequences.

Monotonic numbering, never reused, such as `ADR-0007-queue-choice.md`.

Possible statuses: `Proposed`, then `Accepted`, then `Superseded by ADR-00NN` or `Deprecated`.

**An accepted ADR is not rewritten.** If the decision changes, write a new ADR that supersedes the
old one, and mark the old one. This is what lets you understand later how long a decision governed
the project.

Direct consequence, **superseded ADRs do not go to `archives/`**. They stay in place, marked. Their
value comes precisely from having been true at some point. It is the only exception to the archiving
rule.

An ADR fits on one page. Supporting material goes elsewhere, linked.

What deserves an ADR: what is costly to reverse, what went through a real trade-off, what will
surprise a future reader. Not obvious choices, not those undone in ten minutes.

---

## Maintenance at debrief

For each zone touched by the session:

1. List the pages whose `Scope` overlaps the modified files. `ctx-audit.sh` does it for you.
2. Each overlapping page is **re-read**, not just redated. Redating without reading is the fastest
   way to turn `docs/` into a pitfall.
3. Fix, then set `✅ up to date, verified on <today>`. If the subject is gone, the page leaves via
   `$SKILL/scripts/ctx-archive.sh`, which checks incoming references before moving.
4. Create the missing pages for whatever meets one of the criteria above.
5. Bring `docs/README.md` back in line.
6. Every page above 250 lines is split into two subjects, or moves its narrative to `archives/` if
   it no longer helps decide.
