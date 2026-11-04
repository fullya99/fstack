---
description: Turns an idea into a sourced implementation plan, then into an execution prompt.
argument-hint: [the idea to plan]
---
Idea to plan: $ARGUMENTS

**PLAN** mode of the `fstack` skill. Load the skill, then read `references/MODE-PLAN.md` in full before the first move, command
included: the procedure is in that file, not in the skill.
Phase 5: the execution prompt goes into the brief queue, one entry per plan, and the chat gets a single line:
`bash "$SKILL/scripts/ctx-startup.sh" --write-brief --plan plans/<slug>.md --data "${CLAUDE_PLUGIN_DATA}"`, with the prompt on stdin through the heredoc from `SKILL.md`.
