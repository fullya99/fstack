# Mode MIGRER

> **Le contrat** : un projet qui a déjà une convention de contexte passe en version 5 sans perdre
> une information vraie. Le script simule d'abord, l'opérateur relit le rapport, puis on applique
> sur une branche. Rien n'est poussé ni mergé sans lui.

**Avant d'écrire quoi que ce soit**, charge le skill **`style-redaction`**. S'il manque : français,
ton direct, aucun tiret cadratin, aucun point-virgule.

## Quand ce mode s'applique

| Le projet a | Ce que tu fais |
|---|---|
| un bloc `contexte:convention` en version 3 ou 4 | ce mode |
| trois piliers sans bloc (version 2), ou quatre piliers avec `MEMORY.md` (version 1) | ce mode |
| un bloc en version 5 | le bloc n'est pas réécrit, mais le script rejoue ses gestes sans risque (lignes d'orchestration, anciennes commandes, listes à trier) et dit « rien à faire » s'il n'a rien à poser |
| aucun pilier (version 0) | `scripts/ctx-init.sh`, le mode INIT, pas celui-ci |

Après une mise à jour du plugin, repasse `migrer` sur un projet déjà en version 5 : les gestes ajoutés depuis lui arrivent, le bloc reste tel quel.

## Les étapes

1. **Une branche.** `git switch -c migration-fstack` sur un arbre propre. Le script ne crée
   ni branche ni commit.
2. **La simulation.** `bash "$SKILL/scripts/ctx-migrer.sh" --root <racine>` n'écrit rien. `<racine>` est l'argument de
   la commande s'il est donné, sinon `.`. Résous `$SKILL`
   comme dans `SKILL.md`.
3. **La revue avec l'opérateur.** Lis le rapport section par section, voir plus bas. Chaque point
   qui demande un jugement est à lui.
4. **L'application.** `bash "$SKILL/scripts/ctx-migrer.sh" --root <racine> --appliquer` pose le bloc en
   version 5 et réécrit les commandes citées. Un second passage ne change rien.
5. **Les décisions de la revue.** Applique à la main ce que l'opérateur a tranché.
6. **Une clôture complète**, mode CLÔTURE, jusqu'à `ctx-audit.sh --strict` sans blocage. Elle
   vérifie les piliers, remplit les trous que le bloc neuf révèle et fait tourner les journaux.
7. **La PR, ouverte par l'opérateur.** Tu prépares la description : version de départ, ce qui a
   changé, ce qui reste ouvert. Retour arrière : fermer la PR, ou `git revert` du merge.

## Lire le rapport

| Section | Ce que le script fait | Ce que l'opérateur tranche |
|---|---|---|
| Bloc | pose ou réécrit le bloc, garde les clés connues, répare un bloc mal fermé | la `langue` devinée, le profil détecté |
| `taille:` | la retire si elle égale la mesure, sinon la passe en `taille-forcee:` | garder la valeur forcée, ou la retirer |
| Conventions existantes | déclare `MEMORY.md`, `PROJECT.md`, `TASKS.md`, `ETAT.md`, `AGENTS.md` porteur dans `ecarts:` | la justification à compléter, et s'il faut répartir `MEMORY.md` |
| Règles `globs:` | propose le diff vers `paths:`, n'applique jamais | appliquer le diff, ou non |
| Copies locales | les liste à retirer, ne supprime rien | le retrait, après avoir vu qu'aucune copie ne porte un réglage propre |
| Script local | lit ses seuils (`SEUIL=`, `MAX_...=`) et les reporte dans `seuils:` ou `ajourne:` | le reste de sa logique, à reprendre à la main |
| Commandes | réécrit `/cloture-session:cloture`, `/cloture`, `/deep-plan:planifier`, `/planifier`, `/init-contexte`, `/reprise-session`, `/audit-md` vers `/fstack:*` | relire le diff de `CLAUDE.md` |
| Profils d'agents | liste ceux qui s'appellent `syz-*` ou `gz-*` ou qui figent un identifiant de modèle | les remplacer par `fstack:<profil>`, ou les déclarer dans `ecarts:` |

## Les règles qui tiennent

- **Rien ne se supprime.** Un fichier qui sort va dans `archives/` par `ctx-archive.sh`, avec sa
  raison. Pour un dossier de copie locale, le retrait est la décision de l'opérateur, git garde
  l'historique.
- **`MEMORY.md` n'est jamais dissous en silence.** Le script le déclare, la répartition de son
  contenu (décisions, pièges, préférences) se propose dans la PR et l'opérateur tranche.
- **Un sous-module n'est pas touché** depuis le dépôt parent, il se migre dans son propre dépôt.
- **Le bloc posé se relit.** La langue et le profil sont devinés, ils se vérifient dans le diff
  avant la clôture.
