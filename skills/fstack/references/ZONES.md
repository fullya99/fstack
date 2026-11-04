# ZONES: splitting the map without splitting the state

> A zone gives its own map to a directory too big to fit in the root CODEMAP. State and log stay
> single, a zone never has its own TODOS or CHANGELOG.

## What a zone is, and what it is not

A zone is a directory that carries `CODEMAP.md`, and optionally `CLAUDE.md`. Nothing else. It
differs from a standalone level, which carries the three pillars and gets its own debrief, as with
a monorepo package or a sub-project shipped separately.

| | Zone | Standalone level | `docs/modules/` page |
|---|---|---|---|
| What it carries | `CODEMAP.md`, optional `CLAUDE.md` | the 3 full pillars | a knowledge page |
| Debriefed | within the parent's debrief | separately, the parent points | updated in phase 3 |
| When to pick it | a code directory too big for the root CODEMAP | a sub-project with a life of its own | a subject worth explaining, not filing |

`ctx-audit.sh` tells level from zone by the presence of the three pillars: a lone `CODEMAP.md` is
a zone, all three together are a level, section 1b of the audit.

## When to create a zone

A directory is a candidate if it holds at least 25 files, or takes more than 30 lines of the root
CODEMAP, or has its own `docs/modules/` page of more than 100 lines. The script proposes,
`ctx-audit.sh --budget` lists the candidates, the skill decides.

One zone per subject you hold in mind at the same time. Never a ten-line zone stitched together to
make a number, those lines stay in the root CODEMAP or join a neighboring zone.

By project size: small, no zone. Medium, a zone where the root CODEMAP overflows, not before.
Large, zones from SETUP, the root CODEMAP is born as an index.

## What a zone carries

**`<zone>/CODEMAP.md`**, mandatory, template `templates/CODEMAP-zone.md`. Role in one sentence,
zone tree, entry points, flows, pitfalls. This is where the sensitive zones that concern the zone
go, no longer the root CODEMAP. Target 150 lines.

**`<zone>/CLAUDE.md`**, optional, template `templates/CLAUDE-zone.md`, 30 lines at most. Only the
rules that must hold when editing in the zone, worded as facts about the zone.

```bash
bash "$SKILL/scripts/ctx-init.sh" --zone src/<dir>                 # creates the map
bash "$SKILL/scripts/ctx-init.sh" --zone src/<dir> --with-claude   # creates the map and the rules
```

## What stays at the root

The no-exception prohibitions, security, whatever holds everywhere, never only in a zone. An agent
working elsewhere in the repo would not see a zone rule, this is the lazy-leaf trap: a constraint
that must hold everywhere and was only written in `<zone>/CLAUDE.md` does not exist for anyone
else.

The precedence trap, documented on a real case (Knack, 2026-05-22,
https://getknack.ai/blog/agents-md-monorepo): a root rule said "always run the full suite", a
service rule said "this service filters its tests". The service rule was closer and should have
won on paper, the model followed the root because it was worded as an imperative. Consequence for
writing: the root carries no imperative that contradicts a zone, and a zone words its rules as
facts about itself, never as general orders.

## What each reader loads

For `<zone>/CLAUDE.md`:

| Reader | Behavior |
|---|---|
| Claude Code | on demand, when a file in the zone is read, never before (official docs, memory.md) |
| Codex | `AGENTS.md` in the same place, merged root to cwd, 32 KiB cumulative across all files on the path |
| Hermes | nothing loads it |
| OpenClaw | nothing loads it |

For `<zone>/CODEMAP.md`: everyone, on demand, it is an ordinary `.md` file, no special mechanism
loads or blocks it.

Direct consequence: the map is the portable part of the zone, it travels across all readers. Zone
rules are a convenience specific to Claude Code and Codex, not a guarantee. A constraint that must
hold across all readers goes at the root, never only in `<zone>/CLAUDE.md`.

## The root CODEMAP after the split

It becomes an index. A "Zones" table that points, without copying:

| Zone | Role | Map |
|---|---|---|
| `src/api` | exposes the HTTP routes | `src/api/CODEMAP.md` |

Plus a one-level tree, the global entry points, the global flow and the sensitive zones that
belong to no zone. A sensitive zone that concerns a specific zone lives in its map, not here.

## Maintenance

At each debrief, the map of every zone touched is updated in the same pass as the three pillars. A
zone that exceeds 250 lines splits in two. A zone whose directory disappears goes to the archive
through `$SKILL/scripts/ctx-archive.sh`, never by hand, and the root CODEMAP's "Zones" table loses
its row in the same move.
