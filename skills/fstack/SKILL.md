---
name: fstack
description: "Keeps a project's context docs true and short from one session to the next, whatever its type or size. Six modes: setup installs the convention, plan writes a sourced plan and its execution prompt, debrief wraps up the session before a context reset, brief says where we left off, check tests CLAUDE.md and AGENTS.md against the code, upgrade brings an old convention up to date. Three pillars CODEMAP.md, TODOS.md and CHANGELOG.md, plus docs/ and archives/, set by the contexte:convention block. Triggers on: wrap up, end of session, before clear, debrief, resume, where were we, brief me, make a plan, plan this, check the CLAUDE.md, the docs are bloating, TODOS is too long, archive what is stale, living docs, upgrade the convention, /fstack. Not for writing or editing prose, that is style-redaction."
license: MIT
metadata:
  version: 1.0.0-rc.6
  hermes:
    tags: [documentation, session, housekeeping, changelog, codemap, context-budget, planning, audit]
---

# fstack

> The repo alone must be enough to resume work. What only lives in the conversation does not exist.

Load the `style-redaction` skill before writing. If it is missing: direct tone, no em dash, no
semicolon, the project's prose language.

## The base

- Three pillars at the root: `CODEMAP.md` (where), `TODOS.md` (now), `CHANGELOG.md` (what changed).
- `CLAUDE.md` holds what is always true, short, with no state and no narrative.
- `docs/` only holds what is true. `archives/` absorbs the rest, with a header, and is never read as a source of truth.
- The `contexte:convention` block (`version: 5`), in `CODEMAP.md`, declares the real paths, the profile and the thresholds.
- In front of every line, ask: who owns this sentence?

## Choose the mode

In Claude Code, the command decides. Without a command, the intent decides. Read the mode's file in full, that file only, before the mode's first move: without it, you play
the procedure from memory, and a pass measured on 2026-11-02 ran the debrief check before having opened it.

| Mode | Command | Intent | Read |
|---|---|---|---|
| setup | `/fstack:setup` | install the convention, the kit is missing | `references/MODE-SETUP.md` |
| debrief | `/fstack:debrief` | end of session, before a context reset, the docs are bloating | `references/MODE-DEBRIEF.md` |
| brief | `/fstack:brief` | start of session, where we left off, restart prompt | `references/MODE-BRIEF.md` |
| plan | `/fstack:plan` | make a plan, frame an idea | `references/MODE-PLAN.md` |
| check | `/fstack:check` | CLAUDE.md or AGENTS.md too long or wrong | `references/MODE-CHECK.md` |
| upgrade | `/fstack:upgrade` | bring an old convention up to date | `references/MODE-UPGRADE.md` |

The generic restart prompt is requested through brief mode (`/fstack:brief prompt`).

Not this skill: writing or fixing a text, that is `style-redaction`. Adding a feature or fixing a
bug needs no mode. A `CLAUDE.md` to rewrite from scratch without a check goes through `references/BUDGET.md`.

## Resolve `$SKILL`, once per session

The scripts live in the skill, not in the project. Resolve the path before the first call:

```bash
ANCESTORS="$(d="$PWD"; while [ "$d" != "/" ]; do echo "$d/.agents/skills/fstack"; d="$(dirname "$d")"; done)"

SKILL="$(for d in "${CLAUDE_PLUGIN_ROOT}/skills/fstack" \
  ".claude/skills/fstack" $ANCESTORS \
  "$HOME/.claude/skills/fstack" \
  "$HOME/.codex/skills/fstack" "$HOME/.agents/skills/fstack" \
  $(find "$HOME/.claude/plugins/cache" -maxdepth 5 -type d -path '*/skills/fstack' 2>/dev/null | sort -r) \
  $(find "$HOME/.claude/plugins/marketplaces" -maxdepth 5 -type d -path '*/skills/fstack' 2>/dev/null); do
  [ -f "$d/scripts/ctx-audit.sh" ] && echo "$d" && break
done)"
[ -n "$SKILL" ] || echo "skill not found, do the steps by hand without the script"
```

Observable: `$SKILL` points to a folder that contains `scripts/ctx-audit.sh`. The reason for the order is in `references/RESOLUTION.md`.

## Debrief marker and restart prompt

These commands live here because `CLAUDE_PLUGIN_DATA` is only substituted in this file. Outside
Claude Code it is empty, and the script exits without writing anything. At the end of a debrief, after the commit:

```bash
bash "$SKILL/scripts/ctx-startup.sh" --write-marker --data "${CLAUDE_PLUGIN_DATA}"
bash "$SKILL/scripts/ctx-startup.sh" --write-brief --data "${CLAUDE_PLUGIN_DATA}" <<'END_BRIEF_7Q3'
<the restart prompt, written following references/MODE-BRIEF.md>
END_BRIEF_7Q3
```

The delimiter is quoted, so `$` and backticks pass through as is. If it appears alone on a line of
the prompt, the rest would be run as commands: change it.

At the end of plan mode, a plan's prompt, one entry per plan that does not overwrite the handover.
`--after <plan>` if this plan consumes what another delivers:

```bash
bash "$SKILL/scripts/ctx-startup.sh" --write-brief --plan plans/<slug>.md --data "${CLAUDE_PLUGIN_DATA}" <<'END_BRIEF_7Q3'
<the execution prompt, written following references/plan/PROMPT.md>
END_BRIEF_7Q3
```

On resume (`/fstack:brief open`), read the next queue entry (the handover first,
then the plans in order), which is then marked played. `--name <entry>` picks one.
`--list-briefs` shows the queue without playing anything, `--settle <entry>` marks as played an entry
executed another way:

```bash
bash "$SKILL/scripts/ctx-startup.sh" --read-brief --data "${CLAUDE_PLUGIN_DATA}"
bash "$SKILL/scripts/ctx-startup.sh" --list-briefs --data "${CLAUDE_PLUGIN_DATA}"
```

## After a compaction

Only the first 5,000 tokens of this file come back, and a mode file that was read is now just a
summary. A mode in progress continues by rereading its `references/MODE-*.md` file, never
from memory. The startup hook reminds you when the session resumes from a compaction.

## Orchestrate

The main session frames, arbitrates and validates. Everything that can be delegated goes to the cheapest profile that meets
its done criterion: `fstack:explorer`, `tester`, `runner`, `builder`, `researcher`, `expert`,
`reviewer`. Table, criteria and instructions in `references/DELEGATION.md`.

## Invariants

- Nothing true is lost. What leaves a surface goes to `archives/` with its reason, never a silent deletion.
- No commit or push without the operator, no secret in a tracked file.
- `archives/` is only read through `ctx-archaeology.sh`.
- Hub MCP speeds things up, it is never a prerequisite.
- No doc written from an assumption, no known false claim left for later.
- The language follows `style-redaction`, otherwise the one declared by the `contexte:convention` block.

## References

| File | When to read it |
|---|---|
| `references/MODE-SETUP.md` | setup mode |
| `references/MODE-DEBRIEF.md` | debrief mode |
| `references/MODE-BRIEF.md` | brief mode, restart prompt |
| `references/MODE-PLAN.md` | plan mode |
| `references/MODE-CHECK.md` | check mode |
| `references/MODE-UPGRADE.md` | upgrade mode, project that already has a convention |
| `references/DELEGATION.md` | delegate to an agent profile |
| `references/MULTI-REPO.md` | parent with submodules, several repos |
| `references/AUTO-MEMORY.md` | debrief in Claude Code, drain the automatic memory |
| `references/CONVENTION.md` | specification of the three pillars and the owner of each piece of knowledge |
| `references/PROJECT-CONFIG.md` | each key of the `contexte:convention` block, default and example |
| `references/BUDGET.md` | thresholds, the move for each file that overflows, `CLAUDE.md` without a check |
| `references/ZONES.md` | when a directory deserves its map |
| `references/DOCS-SYSTEM.md` | organization of `docs/`, ADRs, index |
| `references/ARCHIVING.md` | archive, correct or delete, log rotation |
| `references/PROJECT-PROFILES.md` | adapt the convention to the project type |
| `references/HANDOFF.md` | the "ready for a fresh context" test |
| `references/RESOLUTION.md` | the `$SKILL` loop returns empty or the wrong version |
| `references/plan/PLAN.md` | write a plan, skeleton and task format |
| `references/plan/PROMPT.md` | write the execution prompt |
| `references/plan/RESEARCH.md` | research phase of a plan |
| `references/plan/PLAN-TYPES.md` | triage, sections specific to each type |
| `references/audit-md/four-layers.md` | choose where a `CLAUDE.md` block goes |
| `references/audit-md/ranking-criteria.md` | settle a borderline ranking case |
| `references/audit-md/anti-patterns.md` | justify a deletion |
| `references/audit-md/templates.md` | template for a root file and a page |
| `references/audit-md/agent-files.md` | the repo declares sub-agents |
| `templates/` | templates for the pillars, zones, ADRs and the plan |

## Scripts

All are called with `bash "$SKILL/scripts/<name>"`.

| Script | Role |
|---|---|
| `ctx-init.sh` | detects the terrain, creates what is missing without overwriting anything |
| `ctx-audit.sh` | measures the surfaces and checks the convention |
| `ctx-rotation.sh` | rotates the logs |
| `ctx-archive.sh` | moves a file to `archives/` with its header |
| `ctx-archaeology.sh` | the only door for reading `archives/` |
| `ctx-upgrade.sh` | simulates then applies the move to version 5 |
| `ctx-truth.sh` | checks the docs against the code |
| `ctx-startup.sh` | debrief marker and brief queue, called by the startup hook |
| `ctx-common.sh` | shared functions, not called on its own |
| `check-refs.sh`, `check-agents.sh` | dead references, agent declarations |
