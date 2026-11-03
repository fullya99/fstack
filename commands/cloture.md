---
description: "Clôture de session : synchronise les trois piliers, archive l'obsolète, tient le budget, range le prompt de relance."
argument-hint: [note libre sur la session, optionnel, sans-relance pour ne pas ranger de prompt]
---

Note de session : $ARGUMENTS

Mode **CLOTURE** du skill `fstack`. Charge le skill, puis lis `references/MODE-CLOTURE.md` en entier avant le premier geste, commande
comprise : la procédure est dans ce fichier, pas dans le skill.
Après le commit, écris le témoin (vide hors Claude Code, le script sort sans rien écrire) :
`bash "$SKILL/scripts/ctx-demarrage.sh" --ecrire-temoin --donnees "${CLAUDE_PLUGIN_DATA}"`
Puis, sauf si la note contient `sans-relance`, range le prompt de redémarrage par la commande `--ecrire-relance` de la rubrique « Témoin de clôture et prompt de relance » du `SKILL.md`, avec `--donnees "${CLAUDE_PLUGIN_DATA}"`.
