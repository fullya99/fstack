---
description: Reprise de session, reconstruit le contexte depuis le dépôt et dit où on en était. Avec open, joue le prompt rangé par la dernière clôture. Avec prompt, rend le prompt de redémarrage.
argument-hint: [open | prompt | ce sur quoi travailler, optionnel]
---

Argument : $ARGUMENTS

Mode **RELANCE** du skill `fstack`. Charge le skill, puis lis `references/MODE-RELANCE.md` en entier avant le premier geste.
Argument `open` : lis le prompt rangé par la dernière clôture, puis suis-le après avoir vérifié sa fraîcheur :
`bash "$SKILL/scripts/ctx-demarrage.sh" --lire-relance --donnees "${CLAUDE_PLUGIN_DATA}"`
Argument `prompt` : le seul livrable est le prompt de redémarrage du mode, dans un bloc `text`, rangé aussi par la commande `--ecrire-relance` du `SKILL.md`.
Autre argument : c'est l'intention de la session, elle passe avant la déduction.
