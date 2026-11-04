---
description: Transforme une idée en plan d'implémentation sourcé, puis en prompt d'exécution.
argument-hint: [l'idée à planifier]
---

Idée à planifier : $ARGUMENTS

Mode **PLANIFIER** du skill `fstack`. Charge le skill, puis lis `references/MODE-PLANIFIER.md` en entier avant le premier geste, commande
comprise : la procédure est dans ce fichier, pas dans le skill.
Phase 5 : le prompt d'exécution se range dans la file de relance, une entrée par plan, le chat ne reçoit qu'une ligne :
`bash "$SKILL/scripts/ctx-demarrage.sh" --ecrire-relance --plan plans/<slug>.md --donnees "${CLAUDE_PLUGIN_DATA}"`, le prompt sur stdin par le heredoc du `SKILL.md`.
