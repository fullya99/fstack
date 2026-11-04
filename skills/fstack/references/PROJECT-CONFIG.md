# PROJECT-CONFIG: the `contexte:convention` block

> Everything that varies from one project to another is declared in this block, never in a copied
> script. A project no longer forks a script, it sets a line.

The block opens `CODEMAP.md`. Scripts look for it there first, then in `CLAUDE.md`, `AGENTS.md`,
then the other `.md` files at the root. One line per key, `key: value`, lists separated by commas.
Only `version` is mandatory. Keys and values stay in French, whatever the prose language.

```
<!-- contexte:convention
version: 5
profil: application
piliers: CODEMAP.md, TODOS.md, CHANGELOG.md
docs: docs/
archives: archives/
langue: fr
journal: date-titre
seuils: CODEMAP.md=600, CLAUDE.md=250
ajourne: CLAUDE.md=411@2026-09-07
taille-forcee: moyenne
ignorer: projets/*/context-input/**, legacy/old.sh
exceptions: secret=tests/test_web_sante.py, lien=machines/**
ecarts: MEMORY.md=pilier assumé, voir docs/decisions/ADR-0002
-->
```

| Key | Default | Role |
|---|---|---|
| `version` | 4 if the line is missing | Block version. An older script refuses to run and says so. |
| `profil` | deduced by `ctx-init.sh` | Project type, see `PROJECT-PROFILES.md`. |
| `piliers` | `CODEMAP.md, TODOS.md, CHANGELOG.md` | The three pillars. |
| `docs` | `docs/` | Pages directory. |
| `archives` | `archives/` | Archives directory. |
| `plans` | `plans/` | Plans directory. `plans: docs/plans/` for a repo that files them elsewhere. Used by `ctx-rotation.sh --plans` and the audit's executed-plans check. |
| `langue` | `fr` | Prose language. |
| `journal` | tries all three | `date-titre` (`## YYYY-MM-DD`), `keep-a-changelog` (`## [x] - YYYY-MM-DD`) or `crochets` (`[YYYY-MM-DD] [TYPE]`). |
| `seuils` | those of `BUDGET.md` | `file=lines`, one per file to raise. |
| `taille-forcee` | none | Forces `petite`, `moyenne` or `grande` instead of the measurement. |
| `ajourne` | none | Frozen overshoot, `file=lines@date`. It must not grow any more. |
| `ignorer` | none | Root-relative globs the scripts do not walk, see `ignorer` below. |
| `exceptions` | none | `type=pattern`, shell glob pattern, `**` included. Judgments already made. |
| `ecarts` | none | Accepted deviation from the convention, with its justification. |

## `ignorer`

The scripts walk everything the disk holds, **git-ignored files included**: a local note, an
ignored `context-input/`, a deliverable or a `CLAUDE.local.md` all count as context. Only heavy
generated output is pruned, recognized by its nature and never from the `.gitignore`:

- a fixed list: `node_modules`, `vendor`, `.venv`, `venv`, `dist`, `build`, `target`, `.next`,
  `__pycache__`, `.cache`, `.gradle`, `Pods`, `.dart_tool`, `.nuxt`, `.svelte-kit`, `.turbo`,
  `.parcel-cache`, `.terraform`, `.pytest_cache`, `.mypy_cache`, `.tox`.
- any folder with a `CACHEDIR.TAG` whose first line is the standard's signature
  (`Signature: 8a477f597d28d172789f06886806bc55`), Cargo drops one in `target/`.
- a game engine's folders, **only if its marker exists**, at the root or down to depth 3
  (`game/`, `clients/godot/`): Unity (`Library`, `Temp`, `Logs`, `obj`, `UserSettings` if
  `ProjectSettings/ProjectVersion.txt` exists), Unreal (`Intermediate`, `Binaries`,
  `DerivedDataCache`, `Saved` if a `*.uproject` exists), Godot (`.godot` if `project.godot`
  exists). An Unreal plugin (`Plugins/*/*.uplugin`, depth 5) prunes its `Intermediate` and its
  `Binaries`. Folders are read from the engine root, never by name alone: an ordinary project
  `Library/`, even next to a Unity `game/`, is still walked. At most 20 engine roots, the audit
  says how many exceed that. A deeper engine is covered with `ignorer:`.

`ignorer:` covers the last case: what git tracks but is not part of the project, an old repo
imported as is. These are root-relative globs, separated by commas:
`ignorer: projets/*/context-input/**, legacy/old.sh`. A glob ending in `/**`, `/*` or `/` skips the
folder's content, `**/x` means `x` at any depth, any other glob skips the targeted path. A glob
containing a space is ignored. These files count neither in the project size nor in the checks of
the audit, `ctx-truth.sh`, `ctx-init.sh` and `ctx-upgrade.sh`.

A pruning is always named: section 10 of the audit says in one line what `ignorer:` skipped, with
the file count, what each recognized engine pruned and the folders pruned by `CACHEDIR.TAG`.
`ctx-init.sh` says it after the size. In section 1, the audit also announces, as info, the `.md`
files that git ignores (outside pruned folders): they remain context for the scripts, but they
travel neither to a colleague nor to another machine.

## `taille-forcee`

The audit measures the project size (under 150 files excluding dependencies: `petite`, 150 to 600:
`moyenne`, beyond: `grande`). `taille-forcee:` forces it and the checks follow the forced value.
When it differs from the measurement, the audit says so as info. A value outside the three is
ignored, the measurement is kept.

The upgrade sets it when an old `taille:` line differs from the measurement. It marks it to
confirm. If the measurement fits, remove the line. A `taille:` line is no longer read since
version 5, the audit asks to remove it or turn it into `taille-forcee:`.

## `seuils`

`file=N` sets the **warning** threshold. The blocker follows in the same report as the defaults,
rounded to the integer: `CODEMAP.md=600` gives a warning at 600 and a blocker at 800, like 300 and
400 by default. A non-numeric value is ignored.

Keys accepted besides file paths:

| Key | Surface | Default warning / blocker |
|---|---|---|
| `reprise` | TODOS resume block | 50 / 80 |
| `cout-reprise` | sum of what a session loads at the start | 600 / 900 |
| `regles-sans-paths` | `.claude/rules/` rules without `paths` | 150 / 200 |
| `memoire-auto` | auto-memory index | 150 / none, outside the repo |
| `ligne` | line length, in characters, in state files | 800 / none, one warning per file |
| `car-CODEMAP.md` | weight of the root CODEMAP, in characters | 30,000 / 40,000 |
| `car-<zone>/CODEMAP.md` | weight of a zone map, in characters | 20,000 / 25,000 |
| `car-TODOS.md` | weight of TODOS, in characters | 20,000 / 30,000 |
| `car-cout-reprise` | sum of what a session loads at the start, in characters | 60,000 / 90,000 |

The `car-` keys read like the others: the value sets the warning, the blocker follows in the same
report. They do not depend on the same file's line threshold, raising `CODEMAP.md=600` does not
raise `car-CODEMAP.md`. Characters are counted without UTF-8 continuation bytes.

## `ajourne`

A ratchet on an existing overshoot, `file=lines@YYYY-MM-DD`, entries separated by commas. As long
as the file does not exceed the frozen value, the warning or blocker is no longer raised and the
audit recalls the entry as info. If it grows beyond, it is a **blocker**. As soon as it falls back
under its warning threshold, the audit warns: "remove the entry". An unreadable entry, or one
whose file no longer exists, also gives a warning.

## `exceptions`

`type=pattern`, shell glob pattern, `*` and `**` also cover `/`. A judgment already made, not a
disabling of the check.

| Type | What it silences | The pattern targets | Example |
|---|---|---|---|
| `fiche` | `docs/` page missing from the index | the page path | `fiche=docs/brouillons/**` |
| `lien` | dead link or missing target | the target as written, from the root, or the page carrying the link | `lien=machines/**` |
| `archive` | archive without a header or outside the index | the archive path | `archive=archives/2025-*` |
| `secret` | suspicious secret value | the file carrying it | `secret=tests/test_web_sante.py` |
| `agent` | agent without `model:` or with a full identifier | the agent path | `agent=.claude/agents/ancien.md` |
| `verite` | claim in the text that `ctx-truth.sh` cannot find (path, script, option, command, count) | the claim as written | `verite=scripts/ancien.sh` |

`ctx-truth.sh` also reads `lien`: a `lien` pattern covers the same claims as a `verite` pattern.
For a count, the pattern is the directory, with or without a trailing `/`.

Submodules are not declared, they are read from `.gitmodules`.
