---
description: Session resume, rebuilds context from the repo and says where we left off. With open, plays the next brief queue entry, a debrief handover or a plan prompt. With prompt, returns the restart prompt.
argument-hint: [open [entry] | prompt | what to work on, optional]
---
Argument: $ARGUMENTS

**BRIEF** mode of the `fstack` skill. Load the skill, then read `references/MODE-BRIEF.md` in full before the first move.
Argument `open`: read the next queue entry, then follow it after checking it is still fresh:
`bash "$SKILL/scripts/ctx-startup.sh" --read-brief --data "${CLAUDE_PLUGIN_DATA}"`
Argument `open <entry>` (`plan-x`, `x` or `handover`): same command, plus `--name <entry>`.
Argument `prompt`: the only deliverable is the mode's restart prompt, in a `text` block, also queued with the `--write-brief` command from `SKILL.md`.
Any other argument: it is the session's intent, and it comes before deduction.
