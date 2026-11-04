# fstack

**Your repo remembers, so your agent does not have to.**

Every session with a coding agent ends the same way. The context resets, and whatever was only
said in the conversation is gone. fstack fixes that at the source: it keeps a small set of context
files in your repo true and short, so the next session (after a `/clear`, a compaction, or three
weeks off) picks up exactly where the last one stopped.

One rule drives everything: **if a piece of information only lives in the conversation, it does
not exist.**

```
/fstack:brief open   ──▶   work   ──▶   /fstack:debrief   ──▶   /clear
        ▲                                                         │
        └─────────────────────────────────────────────────────────┘
```

- Works on any project: app, library, monorepo, game, infra, data, docs-only.
- Six commands, seven agent profiles, one startup hook.
- Plain Bash and git scripts. No MCP server, no database, no network call.
- Never commits or pushes without your go-ahead. Nothing true is lost.

---

## Contents

- [Why](#why)
- [Quick start](#quick-start)
- [Installation](#installation)
- [What gets installed in your project](#what-gets-installed-in-your-project)
- [The commands](#the-commands)
- [A day with fstack](#a-day-with-fstack)
- [The startup hook](#the-startup-hook)
- [The brief queue](#the-brief-queue)
- [Agent profiles](#agent-profiles)
- [The size budget](#the-size-budget)
- [Configuration](#configuration)
- [The scripts, on their own or in CI](#the-scripts-on-their-own-or-in-ci)
- [Coming from an older version](#coming-from-an-older-version)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [What it does not do](#what-it-does-not-do)

---

## Why

Context docs fail in two ways. They go **false**, because nobody updates them when the code moves.
Or they go **long**, because everybody appends and nobody removes. Both end the same way: the
agent reads them, trusts them, and works from a wrong picture.

A real project measured before fstack, 979 files, 83 sessions in 17 days:

| File | Lines | What went wrong |
|---|---|---|
| `CLAUDE.md` | 647 | a 70-line state paragraph, 99 rules with their backstory |
| `CODEMAP.md` | 2,567 | 1,388 lines of "sensitive zones" |
| `TODOS.md` | 6,534 | a 2,579-line resume block, 73 checked boxes never removed |
| `CHANGELOG.md` | 8,283 | 148 entries, some 153 lines long |

Beyond a certain volume of instructions, a model does not just skip the last rule you added, it
follows all of them less well. fstack treats size as an invariant on par with truth: a file that
is correct but too long to read is lost documentation.

So fstack does three things:

1. **Gives every piece of knowledge one owner.** Where things are goes in `CODEMAP.md`, what to do
   next in `TODOS.md`, what changed in `CHANGELOG.md`, what is always true in `CLAUDE.md`. No
   sentence lives in two places.
2. **Checks the docs against the code.** Scripts verify that cited paths, scripts, options, npm and
   make targets, and file counts still exist. A false claim is fixed, not left for later.
3. **Moves what overflows down a layer.** Old log entries go to `archives/`, module detail goes to
   `docs/`, finished plans shrink to a summary. Nothing true is lost, it just stops costing context
   at every startup.

---

## Quick start

```
/plugin marketplace add fullya99/fstack
/plugin install fstack@fstack
```

Then, in your project:

```
/fstack:setup                 # once: installs the convention, overwrites nothing
... work ...
/fstack:debrief               # end of session: syncs the docs, queues a restart prompt
/clear
/fstack:brief open            # next session: resumes from the queued prompt
```

That is the whole loop. Everything else is there when you need it.

---

## Installation

### Requirements

- Bash 3.2 or later (the macOS default works) and git.
- Standard tools: `awk`, `sed`, `grep`, `find`, `cksum`. `timeout` (GNU coreutils) is optional,
  it caps the startup hook's size measurement.
- Native Windows is not tested. WSL gives the scripts the Bash they need.

### Claude Code (recommended)

```
/plugin marketplace add fullya99/fstack
/plugin install fstack@fstack
/reload-plugins
```

This gives you the skill, the six `/fstack:*` commands, the seven agent profiles and the startup
hook. Check it with:

```bash
claude plugin list | grep -A1 fstack@
```

**Update** to a new release:

```
/plugin marketplace update fstack
/reload-plugins
```

After an update, open each of your projects. If the startup hook says a file still cites old
names, run `/fstack:upgrade` there (see [Coming from an older version](#coming-from-an-older-version)).

### Claude Code, skill only

Copy the skill folder, not the plugin folder:

```bash
mkdir -p ~/.claude/skills
cp -r skills/fstack ~/.claude/skills/
```

The skill triggers on plain requests ("wrap up the session", "where were we"). You do not get the
slash commands, the agent profiles or the hook, which only exist in a plugin install.

### OpenAI Codex

Codex reads the same skill folder from a different path:

```bash
cp -r skills/fstack .agents/skills/       # this repo only
cp -r skills/fstack ~/.agents/skills/     # all your repos
```

Ask for a mode by intent ("debrief this session", "make a plan for X").

### Claude web and Cowork

Each GitHub release of this repo carries `fstack.zip`. Download it and upload it as a skill in
Claude's settings. The skill works from intent, there are no slash commands on the web.

### Hermes Agent and OpenClaw

Use the twin package [`fstack-agent`](https://github.com/fullya99/fstack-agent), same convention
and modes, adapted to agents that carry their own memory.

### Optional companion: `style-redaction`

fstack loads [`style-redaction`](https://github.com/fullya99/style-redaction) before writing, if
it is installed. It sets the language per zone of the project and keeps prose free of generated-text
tics. Without it, fstack applies a minimal version of the same rule.

---

## What gets installed in your project

`/fstack:setup` creates what is missing and never touches what exists:

```
your-project/
├── CLAUDE.md          what is always true: rules, commands, constraints. No state, no story
├── CODEMAP.md         where things are, and what touches what. Opens with the convention block
├── TODOS.md           what to do now. A short resume block on top, then the tasks
├── CHANGELOG.md       what changed, and how to roll it back. Newest first
├── docs/              long-form knowledge that is true today: modules, decisions (ADRs), procedures
└── archives/          what became false or cold, each file with a header saying why
```

| File | The one question it answers |
|---|---|
| `CODEMAP.md` | Where is it, and what touches what? |
| `TODOS.md` | What am I doing now? |
| `CHANGELOG.md` | What changed, and how do I roll back? |
| `CLAUDE.md` | What is true all the time? |

There is no `MEMORY.md` catch-all on purpose. Every kind of knowledge already has an owner above,
and a file that owns everything ends up owning nothing.

`archives/` is never read on resume. When the agent needs to know *why* something is done a
certain way, it goes through `ctx-archaeology.sh`, which always prints the archive's provenance
header before the excerpt, so cold text is never mistaken for current truth.

### Large projects get zones

A project over 600 files gets a `CODEMAP.md` (and optionally a `CLAUDE.md`) per important
directory, and the root map becomes an index. Medium projects get a zone only where the root map
overflows. Monorepos give each standalone unit its own three pillars. Projects with git submodules
are debriefed one repo at a time.

### `AGENTS.md` projects

If your project has an `AGENTS.md` and no `CLAUDE.md`, fstack writes there. If a `CLAUDE.md`
appears later, an `@AGENTS.md` import links the two.

---

## The commands

| Command | Use it | Argument |
|---|---|---|
| [`/fstack:setup`](#fstacksetup) | once, to install the convention | a profile, optional |
| [`/fstack:plan`](#fstackplan) | to turn an idea into a sourced plan | the idea |
| [`/fstack:debrief`](#fstackdebrief) | at the end of a session, before a reset | a note, optional, or `no-brief` |
| [`/fstack:brief`](#fstackbrief) | at the start of a session | `open [entry]`, `prompt`, or a topic |
| [`/fstack:check`](#fstackcheck) | when `CLAUDE.md` or `AGENTS.md` feels wrong or long | a file or folder, optional |
| [`/fstack:upgrade`](#fstackupgrade) | after a plugin update, or on an old convention | a project root, optional |

Memory aid: you get a **brief** when you arrive, you give a **debrief** when you leave.

Without a command, the skill still picks the mode from what you ask. "Let's wrap up" runs a
debrief, "where were we" runs a brief, "plan this" runs a plan.

### `/fstack:setup`

Installs the convention in the current project.

1. Detects the terrain: project type, size, existing docs, competing conventions
   (`memory-bank/`, `.cursor/rules`, `.clinerules`, `GEMINI.md`).
2. Creates the missing pillars from templates and writes the convention block at the top of
   `CODEMAP.md`.
3. Reads the code before writing about it: tree, entry points, manifests, CI, README, recent
   commits. Only what a command confirmed goes into the map. The rest becomes a question in
   `TODOS.md`.
4. Wires your `CLAUDE.md` to the convention (how to read the pillars, how to delegate).
5. Checks its own output with `ctx-truth.sh` before handing back.

When an existing convention competes with fstack, you get one question, and your answer rules.
Nothing is dissolved without your decision.

```
/fstack:setup
/fstack:setup lib          # force the profile instead of detecting it
```

### `/fstack:plan`

Turns an idea into a plan an agent can execute in a fresh session.

| Phase | What happens |
|---|---|
| 0. Triage | type (feature, fix, migration, overhaul, infra, docs, investigation, non-code), stack, external surface |
| 1. Research | official docs and current versions of what the plan depends on, sourced and dated. Skipped, and said so, when nothing external is involved |
| 2. Exploration | the code the plan will touch, read for real |
| 3. Questions | five at most, each with its default answer, asked before anything is written. Nothing is written before your yes |
| 4. The plan | `plans/<slug>.md`: tasks, verification gates, rollback, and a Restart notes section the executor keeps current. A `fstack:reviewer` in a fresh context counter-reviews it first, findings ranked Blocker, Major or Moderate, and the plan comes back only once each one is settled |
| 5. The prompt | an execution prompt for a fresh session, stored in the [brief queue](#the-brief-queue) |

You get one line in the chat: the queue entry's name and "reset the context, then
`/fstack:brief open`". The execution session starts clean, without the noise of the research.

A task of two steps and three files does not get a plan. fstack says so and proposes a line in
`TODOS.md` instead.

You can plan several things in one session. Each plan gets its own queue entry and its own
execution session. A plan that needs another one's output is queued after it.

```
/fstack:plan add SSO login with the existing session store
```

### `/fstack:debrief`

Wraps up the session so the repo alone is enough to resume.

| Phase | What happens |
|---|---|
| 0. Frame and measure | what this session touched, current sizes |
| 1. Audit the real state | `ctx-audit.sh` and `ctx-truth.sh`, run against the code, not the docs |
| 2. Sync the pillars | the resume block in `TODOS.md`, the map, one `CHANGELOG.md` entry with its rollback. In Claude Code, the automatic memory is drained into the right owners |
| 3. Document modules | a `docs/` page for what deserves one, an ADR for a decision that commits what follows |
| 4. Purge the obsolete | what became false moves to `archives/` with its reason, in one pass that also fixes incoming links |
| 5. Keep the budget | log rotation, finished plans shrunk to a summary, overflow moved down a layer |
| 6. Fresh-context test | could a new session resume from the repo alone? |
| 7. Lessons, commit, marker | a commit is **proposed**, you approve it. Then a debrief marker is written |
| 8. Report | what changed, what is left |

At the end, the restart prompt for the next session goes into the brief queue. Skip that with:

```
/fstack:debrief no-brief
/fstack:debrief shipped the importer, the CSV edge case is still open
```

### `/fstack:brief`

Rebuilds the context from the repo in about ten lines: where we are, the next step, what to check
first. It reads the resume block of `TODOS.md`, the outline of `CODEMAP.md` and the last three
`CHANGELOG.md` entries. Never a whole pillar, never `archives/`.

```
/fstack:brief                  # where did we leave off?
/fstack:brief open             # play the next entry of the brief queue
/fstack:brief open sso-login   # play that entry
/fstack:brief prompt           # print a restart prompt, also queued as the handover
/fstack:brief the CSV importer # focus the brief on one topic
```

### `/fstack:check`

Audits `CLAUDE.md` and `AGENTS.md` against the code, then shortens them.

1. **Inventory** of every instruction file and what loads it (imports, `.claude/rules/`, zone files).
2. **Verification**: every cited path, command and glob is tested against the repo by
   `check-refs.sh`. Sub-agent definitions are checked by `check-agents.sh`, because a malformed
   agent file is not loaded and nothing says so.
3. **Ranking**, block by block: does this belong in the always-loaded file, a path-scoped rule, a
   `docs/` page, or nowhere?
4. **Contradictions** between files.
5. **Restructuring** proposed as a diff.
6. **Report**, then your validation before anything is applied.

Start from a clean tree. If it is not, the mode asks you to commit first, so every cut stays a
readable diff.

```
/fstack:check
/fstack:check services/api/CLAUDE.md
```

### `/fstack:upgrade`

Brings a project to the current convention (version 5) without losing anything true.

1. On a clean tree, the agent creates a branch, `git switch -c fstack-upgrade`. The script itself
   creates no branch and no commit.
2. A dry run prints a report and writes nothing.
3. You read the report with the agent. Every point that needs judgment is yours.
4. The script applies. A second run changes nothing.
5. A full debrief follows, until `ctx-audit.sh --strict` exits 0 or each remaining warning is
   declared in the block.
6. You open the PR. Rollback is closing it, or reverting the merge.

What the script does on its own, and what it leaves to you:

| It does | You decide |
|---|---|
| installs or rewrites the convention block, repairs an unclosed one | the guessed language and profile |
| declares an existing `MEMORY.md`, `PROJECT.md`, `TASKS.md` in `ecarts:` | whether to split `MEMORY.md`, which is never dissolved silently |
| rewrites old command, agent and script names in `CLAUDE.md` and `AGENTS.md` | rereading that diff |
| carries thresholds from a local copied script into the block | the rest of that script's logic |
| lists local copies of old skills | their removal |
| proposes a `globs:` to `paths:` diff for rules | applying it |

Run it again after each plugin update. On a project already at version 5, the block stays as is and
only the newer moves apply. Nothing to do means no effect.

---

## A day with fstack

**Morning.** You open Claude Code in your project. The hook prints:

```
[fstack] The session resumes cleanly from the last debrief (on 2026-11-03, commit 4f2c9a1).
[fstack] One restart prompt is waiting (handover, produced on 2026-11-03 at commit 4f2c9a1, nothing committed since). /fstack:brief open to resume it.
```

You run `/fstack:brief open`. The agent reads the handover, checks the terrain with the command it
names, and tells you the next step.

**Midday.** A bigger feature comes up. `/fstack:plan add rate limiting to the public API`. After
research and two questions, the plan lands in `plans/rate-limiting.md` and its execution prompt
goes into the queue. You `/clear`, then `/fstack:brief open`, and a fresh session executes the
plan step by step, checking each gate and keeping the plan's Restart notes current.

**Evening.** `/fstack:debrief`. The resume block is rewritten, the changelog gets one entry with
its rollback, a stale doc page moves to `archives/`, and a commit is proposed. You approve it. The
handover for tomorrow is queued.

---

## The startup hook

The plugin registers a `SessionStart` hook on startup, resume, `/clear`, compaction and fork. It
reads your project, never writes to it, never blocks a session (it always exits 0, with a
10-second timeout), and prints at most fifteen lines, each prefixed `[fstack]`. When all is well
it says almost nothing, because every line costs context at every startup.

Not every check runs on every event. The brief queue is announced on startup and after `/clear`.
The forgotten-debrief check runs on startup only. After a compaction, the hook skips the marker,
the queue and the due dates, and reminds the agent to reread the mode file it was following, since
only a summary survives.

What it can tell you:

| Message | Meaning |
|---|---|
| `The session resumes cleanly from the last debrief (on <date>, commit <sha>).` | nothing moved since the debrief |
| `Last debrief on <date> at commit <sha>, 3 commit(s) added since.` | work happened after the debrief |
| `Last debrief on <date> at commit <sha>, the same commit, but files have changed since.` | uncommitted work after the debrief |
| `Last debrief on <date> at commit <sha>, absent from this branch (rebase or other branch).` | you switched branch or rebased |
| `... which left 2 uncommitted file(s).` | the debrief ended with a dirty tree |
| `5 uncommitted file(s) and no recent CHANGELOG entry: a debrief may have been forgotten.` | exactly that |
| `2 due date(s) past or within 3 days in TODOS.md. To settle: ...` | dated tasks to settle: do, postpone or archive |
| `The resume block of TODOS.md dates from <date>, N days ago.` | the resume block may be stale |
| `1 blocker(s) and 2 warning(s) on the context budget.` | a file went over its budget, `/fstack:debrief` tidies it |
| `One restart prompt is waiting (...). /fstack:brief open to resume it.` | the brief queue has an entry |
| `3 restart prompts are waiting. /fstack:brief open plays <next>, ...` | several entries, up to four listed |
| `<file> still cites old fstack names. Run /fstack:upgrade.` | the project predates the current names |
| `Context pillars present but no convention block. /fstack:upgrade to add it.` | the project predates the convention block |
| `Convention block at version 4, the current one is 5. /fstack:upgrade` | the block is older than the plugin |

A project with none of the three pillars gets complete silence.

To get a due-date reminder, write the date into an open task in `TODOS.md`:

```markdown
- [ ] (due 2026-11-10) renew the staging certificate
```

---

## The brief queue

The brief queue holds restart prompts between sessions, outside your repo, in the plugin's data
folder (`~/.claude/plugins/data/fstack-fstack/briefs/<project>/`). Nothing lands in your git tree.

- **One handover**, written by `/fstack:debrief` or `/fstack:brief prompt`. A new one replaces it.
- **One entry per plan**, written by `/fstack:plan`. Plan entries never overwrite the handover.
- **Order**: the handover plays first, then plans in the order they were queued. A plan queued
  with a dependency waits for the plan it depends on.
- **Played entries are kept** as `<entry>.played.md`, so you can still read a prompt after using it.
- Each entry records the commit it was written at. When it plays, you are told how fresh it is.

Useful moves, all through the skill:

| You want to | Ask for |
|---|---|
| resume with the next entry | `/fstack:brief open` |
| play a specific plan | `/fstack:brief open <entry>` |
| see the queue without playing anything | "list the brief queue" |
| mark an entry done because you ran it another way | "settle the `<entry>` brief" |

Outside Claude Code there is no plugin data folder. The prompt is then printed in the chat for you
to keep, and a plan's own Restart notes section is enough to resume it.

---

## Agent profiles

fstack ships seven sub-agent profiles. The main session frames, arbitrates and validates. Work that
can be delegated goes to the cheapest profile that meets its done criterion.

| Profile | Model | Effort | Use it to | Not for |
|---|---|---|---|---|
| `fstack:explorer` | haiku | low | find, read, count, inventory, changing nothing | running tests, explaining a failure |
| `fstack:tester` | haiku | low | run tests, linters, check scripts, return raw output | fixing what fails |
| `fstack:runner` | sonnet | low | apply a mechanical change already decided: rename, patch, regeneration | deciding how |
| `fstack:builder` | sonnet | medium | implement a scoped change with tests and docs | unknown root causes, security, migrations |
| `fstack:researcher` | sonnet | medium | sourced, dated facts from outside the repo | digging through the repo |
| `fstack:reviewer` | sonnet | high | review a diff adversarially, with a fresh context | writing the fix |
| `fstack:expert` | sonnet | high | unknown root causes, migrations, security, delicate code | a scoped change |

Profiles use model aliases, never pinned model identifiers, so they follow your account's current
models. Setup writes three orchestration lines into your `CLAUDE.md` so the main session knows to
delegate.

---

## The size budget

Every surface has a target, a warning and a blocker. `ctx-audit.sh --budget` measures them, and a
debrief brings anything over the line back under it, by moving content to its owner, not by
deleting it.

| Surface | Target | Warning | Blocker |
|---|---|---|---|
| root `CLAUDE.md` | ≤ 100 lines | 150 | 200 lines or 40,000 chars |
| zone `CLAUDE.md` | ≤ 30 | 40 | 60 |
| root `CODEMAP.md` | ≤ 250 | 300 lines or 30,000 chars | 400 lines or 40,000 chars |
| zone `CODEMAP.md` | ≤ 150 | 200 lines or 20,000 chars | 250 lines or 25,000 chars |
| `TODOS.md` | ≤ 150 | 200 lines or 20,000 chars | 300 lines or 30,000 chars |
| resume block of `TODOS.md` | ≤ 40 | 50 | 80 |
| `CHANGELOG.md` | ≤ 30 entries | 40 entries or 1,000 lines | 60 entries or 1,500 lines |
| one changelog entry | ≤ 25 lines | 40 | reported only |
| one `docs/` page | ≤ 200 | 250 | 300 |
| `.claude/rules/` without `paths:` | ≤ 100 in total | 150 | 200 |
| **total resume cost** | **≤ 450 lines** | 600 | 900 lines or 90,000 chars |

What overflows moves down a layer:

- old changelog entries rotate to `archives/changelog/YYYY-MM.md`, the 30 newest stay
- a finished plan becomes a 20-line summary, its full text goes to `archives/`
- module detail leaves the root map for a zone map or a `docs/` page
- state and narrative leave `CLAUDE.md` for `TODOS.md` and `CHANGELOG.md`.

The number only says where to look. What you find there decides the move.

---

## Configuration

Everything that varies per project lives in one block at the top of `CODEMAP.md`. You never fork a
script, you set a line. Only `version` is required.

```
<!-- contexte:convention
version: 5
profil: app
langue: en
journal: keep-a-changelog
seuils: CODEMAP.md=600, CLAUDE.md=250
ajourne: CLAUDE.md=411@2026-12-01
ignorer: vendor/**, legacy/old.sh
exceptions: secret=tests/fixtures/fake_key.txt
ecarts: MEMORY.md=kept as a pillar, see docs/decisions/ADR-0002.md
-->
```

The block's marker, its keys and its enumerated values (`date-titre`, `petite`, `fiche`...) are in
French and stay that way in every project. This is a
frozen contract: changing it would break every project already set up, so it is the one place
where French remains. Everything fstack writes elsewhere follows your project's language.

| Key | Default | What it does |
|---|---|---|
| `version` | `4` if missing | convention version. An older script refuses a newer block and says so |
| `profil` | detected | project type, see below |
| `piliers` | `CODEMAP.md, TODOS.md, CHANGELOG.md` | the three pillar files |
| `docs` | `docs/` | pages directory |
| `archives` | `archives/` | archives directory |
| `plans` | `plans/` | plans directory |
| `langue` | `fr` | prose language, `en` or `fr` |
| `journal` | detected | changelog format: `date-titre` (`## YYYY-MM-DD title`), `keep-a-changelog` (`## [x.y.z] - YYYY-MM-DD`), `crochets` (`[YYYY-MM-DD] [TYPE]`) |
| `seuils` | the budget table | raise a warning threshold, `file=lines`. The blocker scales with it: `CODEMAP.md=600` blocks at 800 |
| `ajourne` | none | freeze a known overshoot, `file=lines@date`. It must not grow further |
| `taille-forcee` | measured | force the size class: `petite`, `moyenne`, `grande` |
| `ignorer` | none | globs the scripts do not walk |
| `exceptions` | none | known exceptions per check type: `fiche`, `lien`, `archive`, `secret`, `agent`, `verite` |
| `ecarts` | none | deliberate departures from the convention, each with its reason |

### Project profiles

Detected by `ctx-init.sh` from the files present, most specific first:

| Profile | Detected from |
|---|---|
| `outillage-agent` | `.claude-plugin/plugin.json`, `SKILL.md`, `skills/*/SKILL.md`, `.claude/skills/` |
| `jeu` (game) | Unity `ProjectSettings/ProjectVersion.txt`, `project.godot`, `*.uproject` |
| `mobile` | `pubspec.yaml`, `android/` with `ios/`, `*.xcodeproj` |
| `monorepo` | `pnpm-workspace.yaml`, `turbo.json`, `nx.json`, `go.work`, `packages/`, `apps/` |
| `desktop` | `src-tauri/`, Electron in `package.json` |
| `infra` | `terraform/`, `ansible/`, `k8s/`, `*.tf`, `Chart.yaml` |
| `data` | `notebooks/`, `*.ipynb`, `dvc.yaml` |
| `lib` | `Cargo.toml` with `src/lib.rs` and no `src/main.rs`, or a `package.json` that exports with no `start` or `dev` script. Other libraries are detected as `app`, force the profile if needed |
| `app` | any common manifest: `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `*.csproj`... |
| `contenu` (content) | `content/`, `posts/` |
| `non-technique` | no code: documents and procedures |

Size is measured too: small under 150 files (one level, no zones), medium 150 to 600 (zones where
the map overflows), large over 600 (zones from the start).

---

## The scripts, on their own or in CI

All scripts live in `skills/fstack/scripts/`, need only Bash and git, and run from the project
root. Most also take `--root <path>`.

| Script | What it does |
|---|---|
| `ctx-init.sh` | detects the project and creates what is missing. `--dry-run` to preview, `--profile <p>` to force the profile, `--zone <dir>` for a zone map, `--with-claude` to add its `CLAUDE.md` |
| `ctx-audit.sh` | drift and budget report. `--budget` for sizes only, `--strict` to fail on warnings, `--json` for tooling |
| `ctx-truth.sh` | checks docs claims against the repo. `--strict` to fail on a false claim, `--info` for borderline cases |
| `ctx-rotation.sh` | rotates the changelog (`--keep 30` by default), `--plans` shrinks finished plans |
| `ctx-archive.sh` | `<file> --reason "..."` moves a file to `archives/` with its header and fixes incoming links, all or nothing. `--replaced-by`, `--summary`, `--verify`, `--dry-run` |
| `ctx-archaeology.sh` | the only way to read `archives/`, provenance first, bounded output |
| `ctx-upgrade.sh` | dry run of the move to version 5, `--apply` to write |
| `check-refs.sh` | dead paths, commands and globs in an instructions file. Verdicts `TRUE`, `FALSE`, `UNVERIFIABLE` |
| `check-agents.sh` | `<dir or file>`, sub-agent files that would silently fail to load |
| `ctx-startup.sh` | the startup hook and the brief queue |

Examples:

```bash
S=~/.claude/skills/fstack/scripts            # or wherever the skill lives

bash $S/ctx-init.sh --dry-run                # what setup would create
bash $S/ctx-audit.sh --budget                # sizes and resume cost
bash $S/ctx-truth.sh                         # false claims in the docs
bash $S/ctx-rotation.sh --dry-run            # what log rotation would move
bash $S/ctx-archaeology.sh "rate limit"      # why was this decided?
bash $S/check-refs.sh --format=md CLAUDE.md AGENTS.md
```

In CI, two lines keep the docs honest on every pull request:

```yaml
- run: bash path/to/fstack/scripts/ctx-audit.sh --strict
- run: bash path/to/fstack/scripts/ctx-truth.sh --strict
```

Both report, neither fixes. `--strict` turns a warning (audit) or a false claim (truth) into exit
code 1.

---

## Coming from an older version

### From an earlier fstack release candidate

Commands, agents and scripts were renamed to English in `1.0.0-rc.6`:

| Before | Now |
|---|---|
| `/fstack:init` | `/fstack:setup` |
| `/fstack:planifier` | `/fstack:plan` |
| `/fstack:relance` | `/fstack:brief` |
| `/fstack:cloture` | `/fstack:debrief` |
| `/fstack:audit` | `/fstack:check` |
| `/fstack:migrer` | `/fstack:upgrade` |
| `chercheur`, `explorateur`, `controleur`, `developpeur`, `executant`, `relecteur` | `researcher`, `explorer`, `tester`, `builder`, `runner`, `reviewer` (`expert` unchanged) |
| `ctx-verite.sh`, `ctx-migrer.sh`, `ctx-demarrage.sh`, `ctx-commun.sh`, `ctx-archeo.sh`, `verif-refs.sh`, `verif-agents.sh` | `ctx-truth.sh`, `ctx-upgrade.sh`, `ctx-startup.sh`, `ctx-common.sh`, `ctx-archaeology.sh`, `check-refs.sh`, `check-agents.sh` |

Update the plugin, then run `/fstack:upgrade` in each project the hook flags. It rewrites the old
names in your `CLAUDE.md` and `AGENTS.md`. A CI file that calls a script by its old name is yours
to fix by hand. Your waiting restart prompts move to the new data layout
on first read, none is lost. The convention block does not change.

### From `clawd-stack`, `cloture-session`, `deep-plan` or `clawd-audit-md`

fstack replaces all four. Two skills on the same cycle compete for triggering, so remove the old
ones:

```
/plugin marketplace add fullya99/fstack
/plugin install fstack@fstack
/plugin marketplace remove clawd-stack       # and cloture-session, deep-plan, clawd-audit-md if present
/reload-plugins
```

Then `/fstack:upgrade` in each project. It rewrites `/cloture`, `/planifier`, `/reprise-session`,
`/audit-md` and the `clawd-stack:*` commands to their `/fstack:*` names.

### From another convention

`memory-bank/`, a root `MEMORY.md`, `.cursor/rules`, `.clinerules`, a homegrown docs script: run
`/fstack:upgrade` (or `/fstack:setup` if there is no pillar at all). Existing files are declared,
never dissolved, and every split is proposed for you to decide.

---

## Troubleshooting

**The skill does not trigger or the commands are missing.** Run `/reload-plugins` and check
`claude plugin list`. The plugin must show as enabled. Skill-only and Codex installs have no slash
commands, ask by intent.

**"skill not found, do the steps by hand".** The skill could not locate its own scripts. It looks,
in order, at the plugin root, the project's `.claude/skills/` and `.agents/skills/` (walking up the
tree), your user skill folders, then the plugin caches. `skills/fstack/references/RESOLUTION.md`
explains each candidate. Reinstalling the plugin fixes it in almost every case.

**It resolves an old version.** Claude Code keeps an installed copy and a marketplace copy of each
plugin. The installed one wins, highest version first. Run `/plugin marketplace update fstack` and
`/reload-plugins`.

**"Restart prompt not stored: CLAUDE_PLUGIN_DATA is missing".** You are outside a Claude Code
plugin install. The prompt stays in the chat, copy it yourself.

**"Hook not working: ctx-common.sh not found".** A partial install. Reinstall the plugin.

**The hook prints nothing.** That is normal when all is well, or when the project has no pillars
yet. Run `/fstack:setup`.

**The audit flags something you want to keep.** Declare it in the block: a known secret-looking
fixture in `exceptions: secret=...`, an accepted overshoot in `ajourne:`, a deliberate departure in
`ecarts:` with its reason. A warning you ignore gets written down, never silenced.

---

## FAQ

**Does it commit or push for me?** Only when you say so. A debrief proposes a commit and makes it
on your go-ahead. Upgrade works on its own branch and leaves the PR and the merge to you. Nothing
is pushed without your request.

**Does it delete things?** Nothing true is lost. A document that went cold moves to `archives/`
with a header saying why, when and what replaces it. A rule that became false is deleted, and the
CHANGELOG entry says so. Done tasks leave `TODOS.md` once the CHANGELOG carries them. Removing a
local copy of an old skill is your call.

**Does it read my whole repo at every startup?** No. The hook reads the debrief marker, `git
status`, the dates in `TODOS.md` and a size measurement of the context files, capped at seven
seconds where `timeout` exists. A brief reads the resume block, the map's outline and three
changelog entries.

**Does it need network access or an MCP server?** The scripts make no network call. The research
phase of a plan uses your agent's web search when the plan depends on something external, and is
skipped otherwise. MCP servers can speed it up, they are never required.

**Why are the block's keys in French?** The block is a frozen contract shared by every project
already set up. The rest of fstack is English. See [Configuration](#configuration).

**Can my docs be in another language?** Yes. Set `langue: en` (or keep `fr`), and fstack writes
prose in that language. File names of the convention stay the same.

**Does it work with `AGENTS.md`?** Yes. It reads both, writes to `AGENTS.md` when that is the only
one, and `/fstack:check` audits both.

**What about monorepos and submodules?** Each standalone unit of a monorepo carries its own pillars
and the root points to them. A submodule is debriefed and upgraded in its own repo, never from the
parent.

**Will it fight with my existing `CLAUDE.md`?** Setup adds a short block to it and touches nothing
else. `/fstack:check` proposes cuts as a diff, you approve each one.

---

## What it does not do

- It does not summarize your session. The goal is a repo that is exact, not a diary.
- It does not guess. What it cannot verify from the code or git history, it asks.
- It does not commit or push without your request, and it never merges or opens a PR.
- It does not write outside your project, except its own data folder (brief queue, debrief
  marker) and, in Claude Code, the project's automatic memory, which a debrief drains into the repo.
- It does not depend on any specific stack, provider or service.

---

## Status and license

`1.0.0-rc.6`, a release candidate. The convention block (version 5) is stable. Releases are listed
on the [releases page](https://github.com/fullya99/fstack/releases).

MIT license.
