# MODE-SETUP: install the convention without overwriting anything

> **The contract**: at the end, the project carries the three pillars, a `contexte:convention`
> block at version 5 that tells the truth about its paths, and three orchestration lines in its
> `CLAUDE.md`. Nothing existing has been overwritten or dissolved.

The script detects the terrain and announces it before writing. The first move depends on what it
finds. An empty template helps nobody, the real work is filling it from the actual code.

```bash
bash "$SKILL/scripts/ctx-init.sh" --dry-run   # shows what would be created, writes nothing
bash "$SKILL/scripts/ctx-init.sh"             # creates what is missing, never overwrites
```

Options: `--root <path>`, `--profile <profile>` to force the profile, `--with-claude` to also
install a zone `CLAUDE.md`, `--zone <directory>` for a zone map alone.

**Observable**: `--dry-run` lists the files to create and the detected profile. After the real
run, `bash "$SKILL/scripts/ctx-audit.sh"` reports no blocker.

## 1. Recognize the profile

The detail of each profile (what counts as a module, what gets checked) is in
`references/PROJECT-PROFILES.md`. Here, only the opening move.

| Situation | First move |
|---|---|
| New project | The kit goes in, you fill it from the code that exists. |
| Existing, documented elsewhere (`doc/`, `documentation/`, `adr/`) | Graft. The script adopts the docs and declares their real paths in the block, with no empty template next to them. Each document gets an owner, what is false leaves through `ctx-archive.sh`. Nothing is dissolved. |
| `AGENTS.md` without `CLAUDE.md` | The script writes into `AGENTS.md`. If a `CLAUDE.md` appears later, an `@AGENTS.md` line at the top links it. |
| Competing convention (`memory-bank/`, `.clinerules`, `.cursor/rules`, `GEMINI.md`) | One question to the operator, whose answer rules. The loser is archived with its reason. |
| `MEMORY.md` from an old version | Its content is split among the owners, `MEMORY.md` is never deleted silently. See `references/MODE-UPGRADE.md`. |
| Unknown project, taken over without docs | Map it from the code and `git log`. You write only what you verified, the rest says "to verify" or gets asked. |
| Small (under 150 files) | The three pillars, no zone, a few pages at most. |
| Medium (150 to 600) | A zone only where the root `CODEMAP.md` overflows. |
| Large (over 600) | The root `CODEMAP.md` is born as an index, each directory that matters gets its map (step 3). |
| Monorepo | Each standalone unit carries its three pillars, the root points. See `references/ZONES.md`. |
| Parent with submodules | Each submodule is debriefed in its own repo, the parent reads it in `.gitmodules` and points. |
| Several instances sharing knowledge | Shared knowledge lives in `kb/core/`, what belongs to one instance in `kb/contrib/`. Each instance points to both. See `references/MULTI-REPO.md`. |
| English-language project | The block declares `langue: en`, the pillars' prose follows. The convention's file names do not change. |
| Non-code project | Profile `non-technique`, the `CODEMAP.md` maps the documents and the procedures. |
| Project already bloated | The graft is a debrief. Install the kit, measure, then go to phase 5 of `references/MODE-DEBRIEF.md`. |

## 2. Read before writing

Tree, entry points, `package.json` or `pyproject.toml` or `Makefile`, the CI, the README, the last
ten commits.

```bash
git log --oneline -10 && ls
```

**Observable**: you opened every module you are about to put in the map. Otherwise it stays out.

## 3. Fill the pillars

1. `CODEMAP.md`: modules with a one-line role, entry points, main flow, external dependencies,
   commands that really work. Check the `contexte:convention` block at the top, `ctx-init.sh`
   fills it. The keys are in `references/PROJECT-CONFIG.md`, it must carry `version: 5`.
2. `TODOS.md`: the real state, what is in progress, what is broken, the visible debt.
3. `CHANGELOG.md`: one bootstrap entry. You do not rewrite past history.
4. `docs/`: one page per module that deserves one, an ADR for a decision already made that
   commits what follows. Criterion in `references/DOCS-SYSTEM.md`. What you cannot infer gets
   asked, never invented.
5. Large project, the zones:

   ```bash
   bash "$SKILL/scripts/ctx-audit.sh" --budget            # lists candidate zones
   bash "$SKILL/scripts/ctx-init.sh" --zone src/<dir>     # creates the map, --with-claude for the rules
   ```

**Observable**: `bash "$SKILL/scripts/ctx-truth.sh"` reports no false claim in what you just wrote.

## 4. Wire the project to the convention

Paste `templates/CLAUDE-snippet.md` into the project's `CLAUDE.md`, create it if it does not
exist. The block carries the reading convention and the three orchestration lines, which
`ctx-init.sh` already adds and does not duplicate on a second run. In substance they say:

- the main session keeps framing, arbitration and validation, and delegates the rest
  (`references/DELEGATION.md`)
- each task goes to the cheapest profile that meets its done criterion
- a subagent report fits in three lines: Done, Left, Surprises

In Claude Code the profiles are called `fstack:<profile>`. Without subagents, these lines read as
a split into verified steps.

**Observable**: `grep -c 'fstack:orchestration' CLAUDE.md` returns 1, even after a second run.

## 5. Finish

```bash
bash "$SKILL/scripts/ctx-audit.sh" --strict
```

No blocker remains. A warning you decide to keep is declared in `ecarts:` or `exceptions:` of the
block, with its reason. If you were asked for a debrief, continue with
`references/MODE-DEBRIEF.md` without asking again.
