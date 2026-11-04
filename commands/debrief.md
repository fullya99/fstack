---
description: "Session debrief: syncs the three pillars, archives what is stale, holds the budget, queues the restart prompt."
argument-hint: [free note on the session, optional, no-brief to skip queuing a prompt]
---
Session note: $ARGUMENTS

**DEBRIEF** mode of the `fstack` skill. Load the skill, then read `references/MODE-DEBRIEF.md` in full before the first move, command
included: the procedure is in that file, not in the skill.
After the commit, write the marker (empty outside Claude Code, the script exits without writing):
`bash "$SKILL/scripts/ctx-startup.sh" --write-marker --data "${CLAUDE_PLUGIN_DATA}"`
Then, unless the note contains `no-brief`, queue the restart prompt with the `--write-brief` command from the "Debrief marker and restart prompt" section of `SKILL.md`, with `--data "${CLAUDE_PLUGIN_DATA}"`.
