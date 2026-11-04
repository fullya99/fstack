# Delegating to agent profiles

The main session orchestrates. It keeps the framing, the arbitration, the irreversible decision
and the validation. The rest goes to a profile, reading included. Valid for any project and any
language.

## The profiles

| Profile | Model | Effort | Tools | For |
|---|---|---|---|---|
| `explorer` | `haiku` | low | read and Bash | find, read, inventory, count, summarize a bounded file |
| `tester` | `haiku` | low | read and Bash | run tests, linters and check scripts, return the raw output |
| `runner` | `sonnet` | low | all | mechanical action already decided: rename, supplied patch, regeneration |
| `builder` | `sonnet` | medium | all | implement a framed change, with its tests and docs |
| `researcher` | `sonnet` | medium | web, read and the session's MCP research tools | external information, sourced and dated |
| `expert` | `sonnet` | high | all | unknown root cause, migration, security, delicate code |
| `reviewer` | `sonnet` | high | no write, Bash only to run checks | adversarial review of a diff against its criteria, always fresh |

They are called `fstack:<profile>`. The model is an alias, it pins no version.

## Choosing

The lowest profile that meets the end criterion. A failure goes up one notch once, then the
orchestrator takes over again. A heavier model as a sub-agent is requested explicitly, it is never
the default.

Cross-check an `explorer` or `tester` output before acting: require paths and numbers, rerun a
`grep` or a `wc` on whatever commits the next step. A cheap profile that chains turns on a
multi-step task ends up costing more than one notch above: `haiku` for a closed contract (find,
count, run), not for an investigation.

## The brief

Four elements, in this order:

1. The spec: what we want, in a few lines.
2. The exact paths: files to read, files to write.
3. The end criterion: a command that passes, or an observable fact.
4. The "aim short" instruction.

A fact the orchestrator measured goes into the brief with its command and date. Without them it
is written as "reported" and the profile rechecks it before building on it.

**The reviewer's package.** A bare `git diff` shows neither new files nor the index state. The
orchestrator prepares the package outside the repo and passes it by path:

```bash
P=<scratchpad>/review; mkdir -p "$P"
git status --porcelain > "$P/state.txt"
git diff HEAD > "$P/diff.patch"
# diff --no-index returns 1 on any difference, so xargs returns 123 on a correct package:
# this code judges nothing, count the package files against state.txt.
git ls-files --others --exclude-standard -z | xargs -0 -r -I{} git diff --no-index /dev/null {} >> "$P/diff.patch"
git status --porcelain | cksum > "$P/fingerprint.txt"   # the tree must not move during the review
split -b 60000 "$P/diff.patch" "$P/slice-"               # a read caps around 25,000 tokens
```

The brief names the project's invariants to check first (secrets, remote writes, exit codes,
what `CLAUDE.md` forbids), before the general correctness pass. At the end, the fingerprint is
recomputed: if it changed, the review covered another tree and is replayed.

The report comes back in three lines, then the requested detail:

```
Done: <what is finished>
Left: <what is not done>
Surprises: <what the brief did not anticipate>
```

## The limits

- Never two agents on the same files.
- At most five agents in parallel.
- An agent does not launch an agent. `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` guarantees it and is recommended.
- A profile does not commit and does not push.
- Each profile carries `maxTurns: 200`: beyond that, Claude Code stops it and returns its output
  as partial, resumable. The profile hands back a checkpoint on its own around turn 180.
- A profile that writes goes through the edit tools, never a heredoc or `sed -i` in Bash.

## Setting the main session

High effort is set in one of these two ways:

```bash
/effort high                       # saved per model
```

```json
{ "effortLevel": "high" }
```

The second goes in the project's `.claude/settings.json`. Never `CLAUDE_CODE_EFFORT_LEVEL`: that
variable also overrides each profile's `effort` and flattens the whole gradation.

## Aliases by platform

On the Anthropic API, `haiku` and `sonnet` follow the latest version of their family. On Bedrock,
Vertex and Foundry, they still point to a 4.x version. To get the wanted version there, pin it
with an environment variable: `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`
and their neighbors.

## Without sub-agents

Codex, Hermes and OpenClaw do not all have sub-agents. The doctrine then becomes a split into
steps, each with its end criterion checked before moving to the next, and the review happens in a
fresh session.
