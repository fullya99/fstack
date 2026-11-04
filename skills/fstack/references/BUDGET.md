# BUDGET: what overflows moves down a layer

> Every surface of the convention has a target, a warning and a blocker. The budget is an
> invariant, on par with truth: a file that is correct but too long to be read is lost
> documentation.

## Why a budget

Measured case, a real project of 979 files, 549 commits, 83 debriefs in 17 days.

| Pillar | Lines | What drifted |
|---|---|---|
| `CLAUDE.md` | 647 | a 70-line state paragraph, 99 rules with their narrative |
| `CODEMAP.md` | 2,567 | sensitive zones 1,388 lines, commands 513 lines with narratives in the comments |
| `TODOS.md` | 6,534 | a 2,579-line resume block, 9 "what this session produced" sections, 73 checked boxes |
| `CHANGELOG.md` | 8,283 | 148 entries, up to 153 lines each |

`ctx-audit.sh` returned 11 minor warnings on this project, none about size. Three causes.

1. No threshold, so no gate. "Aim short" stayed advice.
2. "No silent deletion" was read as "no removal". The resume block became a log, TODOS absorbed
   session reports, CLAUDE.md absorbed state.
3. A single docs level for a fifteen-module project. Module pitfalls fell back into the root
   CODEMAP sensitive zones and into CLAUDE.md, for lack of a closer owner.

The research point that matters, and why we classify before removing. Beyond a certain volume of
instructions, the model does not just start ignoring the last rule added, it follows all the rules
less well, uniformly (HumanLayer, 2025-11-25,
https://www.humanlayer.com/blog/writing-a-good-claude-md). And a uniform summary of a log loses the
constraints it carries, 53% recall after one compaction pass, 10% after five ("The Compaction Cliff
in Long-Running AI Agent Memory", arxiv 2608.22752). Both lead to the same rule: never remove in
bulk, classify each sentence first by what it is, and each one goes to its owner.

The numeric threshold is only a detector, not the rule itself. The splitting criterion stays
semantic, one file answers one question, which is what Diátaxis and DITA say, and neither sets a
maximum length (diataxis.fr, https://diataxis.fr/start-here/). The only style guide to publish a
numeric splitting rule is GitLab, more than five heading levels means several subjects
(docs.gitlab.com, https://docs.gitlab.com/development/documentation/styleguide/). The number says
to go look, what you find says what to do.

## The thresholds

| Surface | Target | Warning | Blocker |
|---|---|---|---|
| root `CLAUDE.md` | ≤ 100 lines | 150 | 200 lines, or 40,000 characters |
| zone `CLAUDE.md` | ≤ 30 | 40 | 60 |
| root `CODEMAP.md` | ≤ 250 | 300 lines, or 30,000 characters | 400 lines, or 40,000 characters |
| zone `CODEMAP.md` | ≤ 150 | 200 lines, or 20,000 characters | 250 lines, or 25,000 characters |
| `TODOS.md` | ≤ 150 | 200 lines, or 20,000 characters | 300 lines, or 30,000 characters |
| "Resume state" block | ≤ 40 | 50 | 80 |
| `CHANGELOG.md` | ≤ 30 entries | 40 entries or 1,000 lines | 60 entries or 1,500 lines |
| one CHANGELOG entry | ≤ 25 lines | 40 | no blocker, reported |
| `docs/` page | ≤ 200 | 250 | 300 |
| one line of `TODOS.md`, `CODEMAP.md`, `CLAUDE.md`, `CHANGELOG.md` (outside code blocks) | no target, only the warning is measured | 800 characters, key `ligne` | no blocker, one warning per file |
| any log (≥ 10 `## YYYY-MM-DD` headings) | same as CHANGELOG | | |
| `.claude/rules/` rules without `paths` (total) | ≤ 100 | 150 | 200 |
| total resume cost | ≤ 450 lines | 600 lines, or 60,000 characters | 900 lines, or 90,000 characters |
| automatic memory index | ≤ 100 | 150 | no blocker, outside the repo |
| finished plan | 20-line summary | over 300 lines, or one open `[ ]` box | no blocker |

The character threshold is one hundred characters per budget line. A line budget does not see a
short file whose every line is a table or a proof: a 191-line `CODEMAP.md` can weigh 126,000
characters and pass under 300 lines. Characters are counted without UTF-8 continuation bytes, an
accented letter is one character, not two. They add to the lines, they do not replace them: the
first threshold crossed speaks. For the resume cost, the message also gives an order of magnitude in
tokens, characters divided by four, which enters no threshold.

Project size, counted in files outside `.git`, dependencies, builds, `archives/`:

| Size | Files | What the convention expects |
|---|---|---|
| small | < 150 | a single level, no zone |
| medium | 150 to 600 | zones where the root CODEMAP overflows |
| large | > 600 | zones from SETUP, the root CODEMAP is an index |

**Warning**: handle at this debrief, or a dated task in TODOS, once only. A warning that comes back
at the next debrief becomes a blocker. **Blocker**: the debrief is not finished while this file
exceeds this threshold.

`ctx-audit.sh --budget` carries exactly these numbers, section 10. Both change together, a
threshold changed here and not in the script makes the audit wrong. Finished plans and the
automatic memory index are read in section 11, which `--budget` skips.

### What the block sets

`seuils: <file>=N` sets the file's **warning** threshold to N. The blocker threshold follows in the
same report as the table's defaults, rounded to the integer: `CODEMAP.md=600` gives a warning at
600 and a blocker at 800, like 300 and 400 by default. Surfaces that are not a file have their own
key: `reprise` (resume block), `cout-reprise`, `regles-sans-paths`, `memoire-auto`. A file's
character threshold has its key `car-<file>` (`car-CODEMAP.md=40000` gives a warning at 40,000
characters and a blocker at 53,333), and the resume cost one `car-cout-reprise`. Raising a file's
line threshold does not raise its character threshold.

`ajourne: <file>=N@YYYY-MM-DD` freezes an overshoot at its value and date. As long as the file does
not exceed N, its warning or blocker is no longer stated, the audit recalls it as information. If
it exceeds N, it is a blocker: a frozen overshoot no longer grows. As soon as it falls back under
its warning threshold, the audit asks to remove the entry.

`taille-forcee: petite|moyenne|grande` imposes the project size instead of the measurement. The
audit says when the measurement contradicts it.

### The total resume cost

What a session loads before the first question: `CLAUDE.md`, the files it imports through `@`
(four hops), the `.claude/rules/` rules without `paths`, the TODOS resume block, the root
`CODEMAP.md` and the last three log entries. Each file can fit in its budget and the sum overflow,
which is the case this threshold catches. `--budget` gives the detail, in lines then characters:
the sum of the same surfaces also counts 60,000 characters as a warning and 90,000 as a blocker.

Beyond five warnings of the same nature in a section ("no status header" over a hundred pages), the
text report prints the first three then a line "and N more of the same nature". The summary's
warning count counts them all, a blocker is never grouped, and `--json` keeps every entry with a
`nature` field.

A rule under `globs:` is never loaded by path, Claude Code only reads `paths`. It therefore counts
among the rules without `paths`, and the audit reports it.

## The move per file

### Resume block

Rewritten from the current state, never by editing the previous block. What leaves it has an owner,
classify before removing.

| What the sentence is | Where it goes |
|---|---|
| An event, something that was done | already in the CHANGELOG, remove it |
| A pitfall, a constraint | module page, or zone CODEMAP, or, with neither module nor zone, `docs/pitfalls/` if the project has one, otherwise the sensitive zones section of `CODEMAP.md`, never both in one project |
| A task | the TODOS list, with its anchor |
| A decision and its why | ADR |
| A discarded lead and why | the decision's ADR, or the page's pitfalls |
| Narrative, emphasis, capitals | nothing, it is not kept |

The block is read under the title `## 🔄 Resume state, <date>`. A French block of an older project
(a `## ...reprise...` title) is also read.

### TODOS

Delete the checked boxes, the fact already lives in the CHANGELOG. Move every "what this session
produced" section to the CHANGELOG, TODOS keeps only the future. Trim tasks without an anchor.
`ctx-audit.sh --budget` counts the boxes and the session sections, section 10.

### CHANGELOG and any log

```bash
bash "$SKILL/scripts/ctx-rotation.sh" --file CHANGELOG.md --dry-run
bash "$SKILL/scripts/ctx-rotation.sh" --file CHANGELOG.md
```

Moves old entries to `archives/<name>/YYYY-MM.md`, keeps the 30 most recent.

The 25-line cap per entry holds **at writing time**. A log is append-only, we do not rewrite the
past, so an old entry that is too long is information, not debt. The audit only warns about it if it
is among the three most recent.
Then shorten any entry over 25 lines, the detail goes in the module page or in
`docs/changes/<date>-<slug>.md`, the entry keeps what, why, rollback, a pointer.

### Root CODEMAP

Create the candidate zones that `ctx-audit.sh --budget` lists, move their sensitive zones and
commands down into them, leave a pointer in the "Zones" table.

```bash
bash "$SKILL/scripts/ctx-init.sh" --zone src/<dir> --with-claude
```

### CLAUDE.md

CHECK mode, otherwise the procedure in the next paragraph.

### docs/ page

Beyond 250 lines, split into two distinct subjects. If a part no longer helps decide, move it to
`archives/` with its header, keep the page short for what remains true.

On an already long file, the audit also reports heading depth beyond four levels. It is the best
sign of two subjects sewn into one page.

### Zone map

Beyond 250 lines, split the zone in two. The criterion is the same as for creating a zone: one
subject you hold in mind at once, never two subjects sewn into one map.

## CLAUDE.md without CHECK mode

When CHECK mode is available, the debrief runs it on a `CLAUDE.md` above the warning threshold, it
makes a cut with proof, and that is the preferred choice when it is there.

Without it, the short procedure, in four layers: the root (loaded every session), a path-bound rule
(`.claude/rules/<zone>.md` with `paths:`, Claude Code only, loaded only when a matching file is
touched), a zone's `CLAUDE.md`, a `docs/` page.

For each line, in this order.

1. Is it a state, a narrative, an event date? None of that belongs here. State goes to TODOS,
   narrative to the module page, the date stays in the CHANGELOG.
2. Is it true everywhere, whatever file is open? It stays at the root.
3. Does it only hold in one zone? It goes down into `<zone>/CLAUDE.md`, or into
   `.claude/rules/<zone>.md` with `paths:` if the project prefers that mechanism.
4. Otherwise, the deciding test: **would removing this line cause a mistake?** No, it goes. Yes, it
   stays, even if the file still exceeds the target.

## Splitting between subagents

On a large codebase, this work splits by zone, one subagent per zone. Each receives the zone path,
its current map and the end criterion: the map fits in 150 lines and every pitfall of the zone is
written in it.

The main session keeps what cannot be split: rewriting the resume block, every archiving decision,
and everything true everywhere, which stays at the root and never only in a zone.

## What the budget does not allow

- Erasing a pitfall to meet the threshold. It goes to its owner, it does not disappear.
- Summarising a log instead of rotating it. `ctx-rotation.sh` moves, it does not condense.
- Moving a cross-cutting rule down into a zone to lighten the root. An agent working elsewhere
  would no longer see it.
- Redating an entry or a page without having re-read it. A false freshness date is worse than none.
- Postponing a blocker to the next debrief. A blocker is handled now, a warning can wait once.
- Replacing content with an `include` or a transclusion to shorten a file. The cost is documented
  elsewhere, an excerpt loses its meaning outside its original context, maintenance drifts through
  small local fixes, and a file full of includes can no longer be read in one pass by an agent. An
  `@file` import loads everything at startup, it lightens nothing.
