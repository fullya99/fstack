# fstack

One context stack for every project. If a piece of information only lives in the conversation, it
does not exist: the repo alone must be enough to resume work, after a `/clear` as after three weeks.

The plugin installs a three-pillar convention, `CODEMAP.md`, `TODOS.md` and `CHANGELOG.md`, plus
`docs/` for long-form knowledge and `archives/` for what became false. Each file fits a budget, and
what overflows moves down a layer.

It replaces `cloture-session`, `deep-plan` and `clawd-audit-md`. Remove them if installed, two
skills on the same cycle compete for triggering.

## Commands

| Command | When |
|---|---|
| `/fstack:setup` | Once, to install the convention in a project |
| `/fstack:plan` | To frame an idea as a sourced plan. Its execution prompt goes into the brief queue, one per plan, several plans per session if needed |
| `/fstack:debrief` | At the end of a session, before a `/clear`. Queues the next session's handover, except with `no-brief`, without touching plan prompts |
| `/fstack:brief` | After a `/clear`, to pick the thread back up in ten lines. `open` plays the next queue entry, the handover first then the plans in order, `open <plan>` picks one |
| `/fstack:check` | To check `CLAUDE.md` and `AGENTS.md` against the code and shorten them |
| `/fstack:upgrade` | To bring an old convention up to date, on a branch, dry run first |

## Installation

```
/plugin marketplace add fullya99/fstack
/plugin install fstack@fstack
```

Or by hand, copying the skill folder and not the plugin folder:

```bash
mkdir -p ~/.claude/skills
cp -r skills/fstack ~/.claude/skills/
```

On OpenAI Codex, same folder, different scan path:

```bash
cp -r skills/fstack .agents/skills/      # repo scope
cp -r skills/fstack ~/.agents/skills/    # user scope
```

With these two routes the slash commands do not come along, they only exist in a plugin install on
Claude Code. The skill still triggers on a plain request.

## What it does not do

It does not commit, does not push, and does not guess. What it cannot deduce from the project, it
asks. Bash and git are enough, no MCP server is required.
