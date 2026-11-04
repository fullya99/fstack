<!-- contexte:convention
version: 5
profil: {{PROFILE}}
piliers: CODEMAP.md, TODOS.md, CHANGELOG.md
docs: {{DOCS}}
archives: {{ARCHIVES}}
langue: {{LANGUAGE}}
-->

# CODEMAP, {{PROJECT_NAME}}

> Where things are, and what touches what.
> Last updated: {{DATE}}

<!-- Aim for 250 lines, blocker at 400. What overflows goes down into a zone map. -->

**In one sentence**: <what this project does, and for whom>.

---

## Tree

```
<root>/
├── <dir>/          # role in one line
├── <dir>/          # role in one line
└── <dir>/          # role in one line
```

<!-- List only what carries meaning. Leave out dependencies, builds, caches. -->

---

## Modules

| Module | Path | Role | Page |
|---|---|---|---|
| <name> | `<path>` | <one line> | [docs](docs/modules/<name>.md) |

---

## Entry points

| Entry | File | Triggered by |
|---|---|---|
| <name> | `<path>:<line>` | <command, route, event, cron> |

---

## Main flow

<The nominal path, in three to six steps, with the files crossed.>

1. `<file>`: <what happens there>
2. `<file>`: <what happens there>
3. `<file>`: <what happens there>

---

## External dependencies

| Dependency | Use | Configuration | Where the credentials are |
|---|---|---|---|
| <service, API, database> | <what it is for> | `<env var or file>` | <location, **never the value**> |

---

## Commands

| Goal | Command |
|---|---|
| Install | `<cmd>` |
| Run | `<cmd>` |
| Test | `<cmd>` |
| Lint and format | `<cmd>` |
| Build | `<cmd>` |
| Deploy | `<cmd>` |

---

## Sensitive areas

<!-- Only what belongs to no zone and no page. A pitfall that concerns a zone goes in its map. -->

- `<path>`: <generated, do not edit by hand, or side effect, or non-obvious convention>

---

## Zones

<!-- A directory that carries its own map. List and POINT, copy nothing. Empty on a small
     project, that is normal. -->

| Zone | Path | Its map | Its rules |
|---|---|---|---|
| <name> | `<path>` | [CODEMAP](<path>/CODEMAP.md) | `<path>/CLAUDE.md` or "none" |

---

## Subprojects

<!-- Monorepo only. A subproject carries its three pillars and is debriefed separately. -->

| Subproject | Path | Its map |
|---|---|---|
| <name> | `<path>` | [CODEMAP](<path>/CODEMAP.md) |
