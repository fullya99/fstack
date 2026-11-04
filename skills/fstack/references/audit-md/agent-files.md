# Agent files

Loaded in phase 2, when the repo declares subagents. Checked on 2026-08-23 against the Claude Code
documentation, `docs.openclaw.ai` and `agentskills.io/specification`.

These files break differently from `CLAUDE.md`. A false `CLAUDE.md` still loads and misleads the
agent. A malformed agent file **does not load at all**, with no error and no warning. The agent
simply does not appear, and its author thinks it is running.

## Where they live

| Location | Scope | Do you touch it? |
|---|---|---|
| `.claude/agents/*.md`, recursive | the project | yes |
| `agents/` of an installed plugin | wherever the plugin is active | no, not your repo |
| `~/.claude/agents/*.md` | all the person's machines | no, you report |
| managed machine settings | the organization | no, you report |

When two definitions share a name, the one closest to the working directory wins. Two files in the
**same** directory with the same `name`: only one loads, and nothing says which.

## The four silent disappearances

The script looks for these first.

1. **No frontmatter.** The file is treated as documentation.
2. **No `name`.** Ignored, the trace goes to the debug log.
3. **`name` with a colon, or starting with a dash.** Rejected at load time.
4. **No `description`.** Ignored, same silence.

YAML that does not parse can fall into the same hole. The most frequent case here is an unquoted
`description` containing `": "`. A strict parser may refuse it, so quote the value. Claude Code
loads it anyway.

## The keys, and what happens to a wrong value

A value outside the list is not refused, it is **ignored**. The agent runs with the default and
nobody sees the instruction go missing.

| Key | Required | Values |
|---|---|---|
| `name` | yes | lowercase and dashes, no colon |
| `description` | yes | text. It alone decides automatic delegation |
| `tools` | no | allowlist. When absent, the agent inherits everything |
| `disallowedTools` | no | denylist, applied before `tools` |
| `model` | no | `sonnet`, `opus`, `haiku`, `fable`, `inherit`, or a full identifier |
| `permissionMode` | no | `default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`, `manual` |
| `maxTurns` | no | positive integer |
| `skills` | no | names of skills preloaded at startup |
| `mcpServers` | no | server names, or inline definitions |
| `hooks` | no | `PreToolUse`, `PostToolUse`, `Stop` |
| `memory` | no | `user`, `project`, `local` |
| `background` | no | `true`, `false` |
| `effort` | no | `low`, `medium`, `high`, `xhigh`, `max` |
| `isolation` | no | `worktree` |
| `color` | no | `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan` |
| `initialPrompt` | no | text, submitted on the first turn when the agent is the main session |

**A key missing from this table is silently ignored.** A typo in a key name disables the option
without a word, and it is one of the hardest defects to spot by eye.

## What the script cannot see

Three things, and they take reading.

**Does the description trigger?** It alone decides. A three-word description never triggers. One
that says what the agent does but not when to call it does not either. The form that works gives
both: the job, then the situations in real words.

**Do two agents step on each other?** Two close descriptions, and the wrong one wins half the time.
It is a contradiction, it goes to phase 4, and you do not settle it.

**Does the body repeat `CLAUDE.md`?** A subagent already inherits the project instructions. What it
repeats is paid twice, and diverges at the first edit of either.

## The rule that never moves

**You never rewrite the body of an agent file.** A broken frontmatter gets fixed, since the right
value can be checked in the table above. The prompt is its author's choice. You report that it
repeats `CLAUDE.md`, you propose the cut, and you wait for a yes.

## For the other readers

Hermes and OpenClaw have no equivalent subagent definition file. In Hermes, every installed skill
becomes a command, and the agent's identity lives in `SOUL.md`. In OpenClaw, a subagent is a
background session launch, configured in `openclaw.json`, not in a markdown file.

What these two platforms have instead, and what deserves the same audit, are their skill catalogs.
Hermes writes some on its own and tweaks them with use, OpenClaw has a workshop where the agent
proposes skills for validation. Duplicates, overlaps, stale skills: same job, same method.
