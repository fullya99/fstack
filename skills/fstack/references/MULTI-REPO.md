# MULTI-REPO: several repos, one convention

> Each repo keeps its three pillars. What changes is who points to whom, and where shared
> knowledge is allowed to live.

## Parent with submodules

The parent points, it does not absorb. Copying a child's docs into the parent creates two versions
that diverge within a few sessions.

- Each equipped child carries its own kit (`CODEMAP.md`, `TODOS.md`, `CHANGELOG.md`) and gets its
  own debrief, in its repo, on its branch.
- The parent's map says for each submodule whether it has its kit. One line is enough:
  `ops/: full kit, see ops/CODEMAP.md`.
- The parent's pointer is a child commit. When the child has moved on, the parent advances it in
  its own debrief, with `git add <submodule>`, and says so in the log.
- A session that starts from the parent and touches a child debriefs both levels, the child first.

Check: `git submodule status` shows neither `+` nor `-` before a path that the parent's map says
is up to date.

## Monorepo with zones

A directory too big for the root map gets its own map, with no state of its own. The detail,
including the difference between a zone and a standalone level, is in `ZONES.md`. A package with
a life of its own carries the three pillars and is handled like a child above.

## Several instances sharing knowledge

The case of several machines or agents working on the same domain, each in its own repo. Two
folders separate what is raw from what is validated.

| Folder | Who writes there | Status |
|---|---|---|
| `kb/contrib/` | each instance, one page per contribution, signed and dated | raw, unverified |
| `kb/core/` | the operator alone, by promoting a contribution | validated, authoritative |

An instance reads `kb/core/` as its source and drops its findings in `kb/contrib/`. It never
edits the base. Promotion happens through an operator commit, who rereads the page and moves it
with `git mv`. A rejected contribution goes to `archives/` with its reason.

`CODEMAP.md` names both folders and the writing rule.

## What `ctx-audit.sh` checks

Sections 6 and 11 of `bash "$SKILL/scripts/ctx-audit.sh"`, with paths taken from `.gitmodules`.

- A path under an uninitialized submodule is not counted as a dead link.
- A child that has the three pillars, while the parent's `CODEMAP.md` or `CLAUDE.md` says it has
  no kit: warning, the parent's map needs fixing.
- A parent pointer older than the child's latest `TODOS.md` change: info, with the
  `git add <submodule>` command to advance it.
- A submodule that is not cloned is skipped silently.

The audit checks neither `kb/contrib/` nor `kb/core/`, writing discipline is the operator's job.
