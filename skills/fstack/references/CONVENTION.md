# CONVENTION: specification of the 3 pillars

> Detailed reference. The operating summary is in `SKILL.md`.
> Everything you write here follows the `style-redaction` skill rule.

## The principle: one question per file

When docs rot, it is rarely because too little was written. It is because one file was asked to do
several jobs. It becomes a wall of exceptions nobody reads, so nobody updates it.

The convention splits knowledge by the question it answers and by its lifespan.

| Surface | Question | Lifespan | Loading |
|---|---|---|---|
| `CLAUDE.md` or `AGENTS.md` | How do we work here? | Very stable | Always, automatic |
| `CODEMAP.md` | Where is it? | Stable, follows the structure | On resume |
| `TODOS.md` | What now? | Volatile | On resume |
| `CHANGELOG.md` | What changed? | Append-only | 2 or 3 entries on resume |
| `docs/` | How does it work in detail? | Long, but dated | On demand, targeted |
| `archives/` | What was true before? | Frozen | Never, except archaeology |

Corollary: never put the same information in two surfaces. Duplicated information will diverge.
Write a pointer, not a copy.

There is **no memory file** in this convention, and it is not an oversight. A file defined as "what
the code does not say" fills up with everything and copies what the other surfaces already carry.
Each piece of knowledge has a single owner.

| What you learned | Where it goes |
|---|---|
| A decision and its why | `docs/decisions/ADR-NNNN-*.md` |
| A module pitfall | The module page, or the map of its zone `<zone>/CODEMAP.md` |
| A discarded lead and why | The decision's ADR, or the page's pitfalls |
| A pitfall with no identifiable module and no zone | `docs/pitfalls/` if the project has one (`docs/pieges/` of an older project is also read), otherwise the sensitive zones section of `CODEMAP.md`, never both in one project |
| A lasting user preference | `CLAUDE.md` |
| Environment constraint, access, available tool | `CODEMAP.md`, dependencies section |
| A dated, perishable external fact | `docs/radar/`, or a `CHANGELOG.md` entry |

The test when writing is one question: **who owns this sentence?** If you cannot answer, it almost
always does not need to be written.

Beware of a namesake. Claude Code keeps its own automatic memory in a file named `MEMORY.md`, under
`~/.claude/projects/<project>/memory/`. It is local to the machine, survives neither a clone nor a
change of workstation, and is not part of this convention. Do not commit it. The debrief drains it
toward the owners (see `AUTO-MEMORY.md`), and nothing is written from the repo into it. The repo
is the authority.

---

## Location and adaptation

The block at the top of `CODEMAP.md` declares the project's real paths. This makes the convention
self-describing. A project that uses `documentation/` instead of `docs/` declares it, and
everything else follows.

```html
<!-- contexte:convention
version: 5
profil: app
piliers: CODEMAP.md, TODOS.md, CHANGELOG.md
docs: docs/
archives: archives/
langue: fr
-->
```

The block, its keys and their values stay in French in every project. Without the block, the
default paths above are assumed. The `version` line is the only required one, it makes scripts that
are too old refuse a block that is too recent. Project size is no longer written, the audit
computes it from the file count outside dependencies: small under 150, medium up to 600, large
beyond. The other keys (thresholds, log, exceptions) and their defaults are in
`references/PROJECT-CONFIG.md`.

**What the stack walks.** Context management never stops at what git tracks: a gitignored file
(local notes, `context-input/`, deliverables, `CLAUDE.local.md`) is still context, so the file list
never comes from `git ls-files` and nothing is excluded because `.gitignore` excludes it. Only
heavy generated output is pruned, recognised by its nature: a fixed list of directories,
directories carrying a `CACHEDIR.TAG`, game engine directories when their marker exists, at the
root or up to three levels down. Every pruning is named by the audit, never silent. A gitignored
file therefore counts, but it travels to neither a colleague nor another machine: the audit
reports it as information. `ignorer:` sets aside what git tracks without being part of the project.

On a medium or large codebase, the map is split by zones. A zone is a directory that carries its
own map, `<zone>/CODEMAP.md`. State and log stay single, at the root. Details are in
`references/ZONES.md`.

**Multi-level**: each self-contained unit (root, monorepo package, sub-project) has its own kit.
The parent does not copy the children's content, it lists them and points to them. A session that
touches several levels updates all of them.

---

## CODEMAP.md, the map

**Role**: find the right file in one read, and understand what breaks when you change it. This
file is neither API documentation nor a tutorial.

**What goes in it**

1. The `contexte:convention` block, profile and paths.
2. **One sentence** saying what the project does. A reader who knows nothing must be able to
   decide in ten seconds whether they are in the right place.
3. **Annotated tree.** The directories that matter, one role line each. No raw `tree` output.
   Cite what carries meaning, omit the noise (dependencies, builds, caches).
4. **Modules.** A table with the name, the path, the role in one line and the `docs/` page if
   there is one.
5. **Entry points.** Where the code really starts: main, server, CLI, handler, cron, worker. It
   is what you look for first and find last.
6. **Main flow.** The nominal path of a request or a job, in three to six steps, with the files
   crossed. Nothing replaces this for a cold reader.
7. **External dependencies.** Services, APIs, databases, queues, accounts. Everything the project
   needs to run. **Never a secret**: say where the key is, not what it is worth.
8. **Commands.** Install, run, test, lint, build, deploy. The real ones, the ones you tested.
9. **Sensitive zones.** Generated code not to edit, files to touch with care, non-obvious
   conventions. Root: only what has neither a zone nor a page. What concerns a zone goes down into
   `<zone>/CODEMAP.md`.
10. **Zones.** A table listing the project's zones and pointing to their map, without copying.
11. The date of the last update.

**What does not go in it**: history (CHANGELOG), tasks (TODOS), the why of decisions
(`docs/decisions/`), implementation details (`docs/modules/`).

**Target length**: target 250 lines, warning at 300, blocker at 400. What overflows goes down into
a zone map, see `references/ZONES.md`.

---

## TODOS.md, the resume state

**Role**: this is the file that makes `/clear` safe. It carries both what remains to do and
exactly where we stood.

**Required structure**

```markdown
# TODOS, <project>

## 🔄 Resume state, YYYY-MM-DD
**Where we are**: <2 to 4 factual lines, what works, what is in place>
**In progress**: <the task started and not finished, with the files involved, or "nothing">
**Next step**: <the very next concrete action, not a vague goal>
**Know before touching**: <pitfalls, unstable state, half-applied work>

## 🔴 Blocked
- [ ] <task>, blocked by <what>, to unblock by <how>

## 🎯 Next steps
- [ ] <actionable task, verb first, with the file or zone>

## 🧹 Debt and improvements
- [ ] <what we know is imperfect, with the impact, not just "refactor">

## 💡 Uncommitted ideas
- <what we may never do, to purge without regret>
```

The resume block is read under the title `## 🔄 Resume state, <date>`. A French block of an older
project (a `## ...reprise...` title) is also read.

**The rules**

The "Resume state" block fits in 40 lines and is **rewritten from the current state** at every
debrief, never by editing the previous block. It is a state, not a log.

A checked task is not archived, it is **deleted**. Its trace is in the CHANGELOG. TODOS keeps only
the future.

Every task mentions an anchor: a file, a module, a command. "Improve performance" is useless after
a `/clear`. "Reduce the N+1 queries in `repo/orders.py:list_orders`" can be picked up at once.

Nothing started may stay outside this file before a `/clear`.

**What leaves the block has an owner**

| What the sentence is | Where it goes |
|---|---|
| An event, something that was done | already in the CHANGELOG, remove it |
| A pitfall, a constraint | module page, or zone CODEMAP, or root sensitive zones if no zone |
| A task | the TODOS list, with its anchor |
| A decision and its why | ADR |
| A discarded lead and why | the decision's ADR, or the page's pitfalls |
| Narrative, emphasis, capitals | nothing, it is not kept |

Three prohibitions in TODOS: no "what this session produced" section, that is CHANGELOG. No
checked box kept, the fact lives in the CHANGELOG. No "decided" section, that is an ADR or
nothing. An unverified claim carries "to verify", and the next session verifies before acting on
it.

**Whole file**: target 150 lines, blocker at 300.

---

## Lasting knowledge, and where it lands

These are the facts no reading of the repo can recover. The table above gives each one's
destination, here is the detail that does not fit in it.

**ADR**, `docs/decisions/`, template `templates/docs/ADR.md`. Context, options considered,
decision, consequences, what should make us reconsider. An accepted ADR is **never rewritten**:
when the decision changes, a new ADR supersedes it and the old one points to the new one.

**Pitfall**, the module's `docs/` page, its zone map, or `CODEMAP.md` sensitive zones if it has
neither. Written as a symptom followed by its cause, not as an instruction. "The API returns 200
with the error in the body" sticks, "beware of errors" is useless.

**User preference**, `CLAUDE.md`, which loads by itself. Requested style, imposed conventions, what
they do not want done. Stays short, permanent items only.

**Environment or access constraint**, `CODEMAP.md` dependencies section. Which service, which
account, which region, where the key lives. **Never the value of a secret.**

**Dated external fact**, `docs/radar/` with its date, or a `CHANGELOG.md` entry if it explains a
change. Perishable by nature, it is re-read or archived.

**Common rules.** Absolute dates, "last week" is wrong by tomorrow. A fact carries its why, not
only its what. A lasting rule that became false is **deleted at once**, not archived, its
disappearance goes in the CHANGELOG if it deserves a trace, only ADRs supersede. When in doubt,
pick the owner that someone working on the subject will re-read.

---

## CHANGELOG.md, the log

**Role**: answer "what changed, when, why and how do we roll back". It is the only append-only
surface of the convention.

**Format**

```markdown
## 2026-08-13, short factual title

**What**: what changed, concretely. Files, behaviours, resources.
**Why**: the need or problem behind it.
**Rollback**: how to undo. Commit to revert, config to restore, reverse migration.
**See also**: `docs/...`, ADR, ticket.
```

**The rules**

Most recent on top. One entry per useful session, not one per commit.

Rollback is not optional as soon as a change touches data, a deployment, a dependency or a
configuration. It is what saves the next session.

Never rewrite the past. A wrong entry is corrected by a new entry that mentions it, not by a
silent edit.

A voluminous entry stays short here and points to `docs/`, or to `changes/<date>-<slug>.md` if the
project has that directory. An entry fits in 25 lines, details go in a page.

Beyond 30 entries the log rotates with `$SKILL/scripts/ctx-rotation.sh` to
`archives/changelog/YYYY-MM.md`, and the file keeps at the top the line that says so. A cold entry
is not false, which is why it goes to the one place not read on resume.

If the project publishes versions, you can adopt the Keep a Changelog structure
(`## [1.4.0] 2026-08-13`, with Added, Changed, Fixed, Removed sections). The what, why, rollback
rule still applies in each section.

---

## What lives in CLAUDE.md, and not here

`CLAUDE.md` is loaded automatically in every session. It is the most expensive surface in context.
Put in it only what must be true at every moment: commands to use, hard prohibitions, lasting user
preferences, style, and the pointer to the context convention.

The rest lives elsewhere and loads on demand. The map in CODEMAP, the state in TODOS, the history
in CHANGELOG, decisions in `docs/decisions/`, detail in `docs/`.

`CLAUDE.md` is what most easily absorbs what has no obvious owner, and that is the risk to watch. A
rule that is not true at every moment does not belong there. Re-read it at every debrief with that
question in mind, and cut. The block to paste is in `templates/CLAUDE-snippet.md`.

`CLAUDE.md` carries no state, no narrative, no event date. Target 100 lines, blocker at 200 lines
or 40,000 characters. A rule that only holds in one zone goes down into `<zone>/CLAUDE.md`, or into
`.claude/rules/<zone>.md` with `paths:` in Claude Code.
