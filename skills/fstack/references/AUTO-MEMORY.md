# AUTO-MEMORY: Claude Code's auto-memory and its draining

> Auto-memory is a notebook Claude Code keeps on its own. It fills with facts that have an owner
> in the convention. The debrief empties it toward those owners.

## Where it lives and how it loads

```bash
ls ~/.claude/projects/<project path>/memory/
```

The folder name is the project's absolute path with every non-alphanumeric character turned into a
dash, for example `-home-ana-code-my-app`. A copy of the repo elsewhere on the machine therefore
has its own memory.

| Fact | Consequence |
|---|---|
| `MEMORY.md` is the index, loaded on its first 200 lines or 25 KB | the rest of the index is invisible |
| Topic files linked from the index are read on demand | they cost nothing until opened |
| Sub-agents do not load it | a fact that lives only there is missing for every delegated agent |
| It is specific to the machine | it does not travel in a clone and is not reread in review |

Source: code.claude.com/docs/en/memory, consulted on 2026-10-11. The files are ordinary
markdown, edit them by hand. Other platforms (Codex, Hermes, OpenClaw, Claude web) have their own
memory, elsewhere and under other rules, this skill does not cover it.

## Draining, at each debrief

List what exists first.

```bash
M=~/.claude/projects/$(pwd | sed 's/[^A-Za-z0-9]/-/g')/memory
wc -l "$M/MEMORY.md" && ls "$M"
```

If absent, there is nothing to drain, the phase closes in one line. Otherwise, each entry gets a
single fate, following the project's ADR grid or, failing that, this one.

| What the entry says | Where it goes |
|---|---|
| Decision and its why | `docs/decisions/ADR-NNNN-*.md` |
| Module pitfall | the `docs/modules/<module>.md` page, or its zone's map |
| Pitfall with no module | `docs/pitfalls/` if the project has one, otherwise the sensitive zones section of `CODEMAP.md`, never both in the same project |
| Lasting operator preference about the project | `CLAUDE.md`, if the budget allows |
| Environment constraint, access, tool | `CODEMAP.md`, dependencies section |
| Dated external fact | `docs/radar/` or a log entry |
| Copy of what already exists | deleted |
| Specific to the machine or the operator, not the project | stays in memory |

A promoted entry is removed from the index and its file deleted. Observable: after the phase, each
deleted or promoted entry has a trace in the diff, and `MEMORY.md` only lists entries that have no
owner in the repo (local paths, workstation preferences, git identity).

## What the audit measures

`bash "$SKILL/scripts/ctx-audit.sh"` reads this project's index, section 11.

- Index above 150 lines: warning. The threshold is set by the block's `memoire-auto` key.
- Entry that copies `CLAUDE.md`: warning, a sentence of 50 characters or more, identical after
  lowercasing and stripping punctuation.
- Memory absent: nothing is said.

## A `MEMORY.md` committed at the root

Projects from older versions of the convention have a `MEMORY.md` in the repo, which played the
role of a fourth pillar. The audit flags it. The skill never dissolves it silently.

1. A project that uses it on purpose declares it in the `ecarts:` line of the `contexte:convention`
   block, with an entry `MEMORY.md=<justification>`. The audit warning then becomes an info that
   cites the justification. Without the entry, the warning stays.
2. Otherwise, `/fstack:upgrade` proposes to spread its content according to the grid above, on a
   branch. The operator decides when reviewing the PR.

No dissolution outside a branch, no deletion until each line has a new owner or a written reason to
disappear. The mode that carries the phase is described in `MODE-DEBRIEF.md`, the upgrade in
`MODE-UPGRADE.md`.
