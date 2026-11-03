---
name: fstack
description: "Tient la documentation de contexte d'un projet vraie et courte d'une session à l'autre, quel que soit son type ou sa taille. Six modes : init installe la convention, planifier écrit un plan sourcé et son prompt d'exécution, cloture range la session avant un redémarrage de contexte, relance dit où on en était, audit vérifie CLAUDE.md et AGENTS.md contre le code, migrer remet une ancienne convention à jour. Trois piliers CODEMAP.md, TODOS.md et CHANGELOG.md, plus docs/ et archives/, réglés par le bloc contexte:convention. Se déclenche sur : clôture, fin de session, avant de clear, reprends, où on en était, fais un plan, planifie, audite le CLAUDE.md, la doc gonfle, TODOS est trop long, archive ce qui est obsolète, doc vivante, migrer la convention, /fstack. Pas pour rédiger ou corriger un texte, c'est style-redaction."
license: MIT
metadata:
  version: 1.0.0-rc.4
  hermes:
    tags: [documentation, session, housekeeping, changelog, codemap, context-budget, planning, audit]
---

# fstack

> Le dépôt seul doit suffire à reprendre le travail. Ce qui ne vit que dans la conversation n'existe pas.

Charge d'abord le skill `style-redaction` avant d'écrire. S'il manque : ton direct, aucun tiret
cadratin, aucun point-virgule, langue de la prose du projet.

## Le socle

- Trois piliers à la racine : `CODEMAP.md` (où), `TODOS.md` (maintenant), `CHANGELOG.md` (ce qui a changé).
- `CLAUDE.md` porte ce qui est vrai tout le temps, court, sans état ni récit.
- `docs/` ne contient que du vrai. `archives/` absorbe le reste, avec un en-tête, et ne se lit jamais comme source de vérité.
- Le bloc `contexte:convention` (`version: 5`), dans `CODEMAP.md`, déclare les chemins réels, le profil et les seuils.
- Devant chaque ligne, demande : qui est propriétaire de cette phrase ?

## Choisir le mode

Chez Claude Code, la commande décide. Sans commande, l'intention décide. Lis le fichier du mode en entier, lui seul, avant le premier geste du mode : sans lui, tu joues la
procédure de mémoire, et une passe mesurée le 2026-11-02 a lancé le contrôle de clôture avant de l'avoir ouvert.

| Mode | Commande | Intention | Lire |
|---|---|---|---|
| init | `/fstack:init` | installer la convention, le kit manque | `references/MODE-INIT.md` |
| cloture | `/fstack:cloture` | fin de session, avant un redémarrage de contexte, la doc gonfle | `references/MODE-CLOTURE.md` |
| relance | `/fstack:relance` | début de session, où on en était, prompt de redémarrage | `references/MODE-RELANCE.md` |
| planifier | `/fstack:planifier` | faire un plan, cadrer une idée | `references/MODE-PLANIFIER.md` |
| audit | `/fstack:audit` | CLAUDE.md ou AGENTS.md trop long ou faux | `references/MODE-AUDIT.md` |
| migrer | `/fstack:migrer` | remettre une ancienne convention à jour | `references/MODE-MIGRER.md` |

Le prompt de redémarrage générique se demande par le mode relance (`/fstack:relance prompt`).

Pas ce skill : rédiger ou corriger un texte, c'est `style-redaction`. Ajouter une fonction ou
corriger un bug ne demande aucun mode. Un `CLAUDE.md` à réécrire de zéro sans audit passe par `references/BUDGET.md`.

## Résoudre `$SKILL`, une fois par session

Les scripts vivent dans le skill, pas dans le projet. Résous le chemin avant le premier appel :

```bash
ANCETRES="$(d="$PWD"; while [ "$d" != "/" ]; do echo "$d/.agents/skills/fstack"; d="$(dirname "$d")"; done)"

SKILL="$(for d in "${CLAUDE_PLUGIN_ROOT}/skills/fstack" \
  ".claude/skills/fstack" $ANCETRES \
  "$HOME/.claude/skills/fstack" \
  "$HOME/.codex/skills/fstack" "$HOME/.agents/skills/fstack" \
  $(find "$HOME/.claude/plugins/cache" -maxdepth 5 -type d -path '*/skills/fstack' 2>/dev/null | sort -r) \
  $(find "$HOME/.claude/plugins/marketplaces" -maxdepth 5 -type d -path '*/skills/fstack' 2>/dev/null); do
  [ -f "$d/scripts/ctx-audit.sh" ] && echo "$d" && break
done)"
[ -n "$SKILL" ] || echo "skill introuvable, fais les etapes a la main sans le script"
```

Observable : `$SKILL` pointe un dossier qui contient `scripts/ctx-audit.sh`. Le pourquoi de l'ordre est dans `references/RESOLUTION.md`.

## Témoin de clôture et prompt de relance

Ces commandes vivent ici parce que `CLAUDE_PLUGIN_DATA` n'est substituée que dans ce fichier. Hors
Claude Code elle est vide, le script sort sans rien écrire. En fin de clôture, après le commit :

```bash
bash "$SKILL/scripts/ctx-demarrage.sh" --ecrire-temoin --donnees "${CLAUDE_PLUGIN_DATA}"
bash "$SKILL/scripts/ctx-demarrage.sh" --ecrire-relance --donnees "${CLAUDE_PLUGIN_DATA}" <<'FIN_RELANCE_7Q3'
<le prompt de redémarrage, rédigé selon references/MODE-RELANCE.md>
FIN_RELANCE_7Q3
```

Le délimiteur est entre apostrophes, donc `$` et accents graves passent tels quels. S'il apparaît
seul sur une ligne du prompt, le reste serait exécuté comme des commandes : change-le.

À la reprise (`/fstack:relance open`), lire le prompt rangé, qui est ensuite marqué joué :

```bash
bash "$SKILL/scripts/ctx-demarrage.sh" --lire-relance --donnees "${CLAUDE_PLUGIN_DATA}"
```

## Après un compactage

Seuls les 5 000 premiers tokens de ce fichier reviennent, et un fichier de mode lu n'est plus
qu'un résumé. Un mode en cours se poursuit en relisant son fichier `references/MODE-*.md`, jamais
de mémoire. Le hook de démarrage le rappelle quand la session reprend d'un compactage.

## Orchestrer

La session principale cadre, arbitre et valide. Tout ce qui se délègue part au profil le moins cher qui tient
son critère de fin : `fstack:explorateur`, `controleur`, `executant`, `developpeur`, `chercheur`, `expert`,
`relecteur`. Table, critères et consignes dans `references/DELEGATION.md`.

## Invariants

- Rien de vrai ne se perd. Ce qui sort d'une surface part dans `archives/` avec sa raison, jamais en suppression silencieuse.
- Aucun commit ni push sans l'opérateur, aucun secret dans un fichier tracké.
- `archives/` ne se lit que par `ctx-archeo.sh`.
- Hub MCP accélère, il n'est jamais un prérequis.
- Aucune doc écrite depuis une supposition, aucune affirmation connue fausse laissée pour plus tard.
- La langue suit `style-redaction`, sinon celle déclarée par le bloc `contexte:convention`.

## Références

| Fichier | Quand le lire |
|---|---|
| `references/MODE-INIT.md` | mode init |
| `references/MODE-CLOTURE.md` | mode cloture |
| `references/MODE-RELANCE.md` | mode relance, prompt de redémarrage |
| `references/MODE-PLANIFIER.md` | mode planifier |
| `references/MODE-AUDIT.md` | mode audit |
| `references/MODE-MIGRER.md` | mode migrer, projet qui a déjà une convention |
| `references/DELEGATION.md` | déléguer à un profil d'agent |
| `references/MULTI-DEPOTS.md` | parent à sous-modules, plusieurs dépôts |
| `references/MEMOIRE-AUTO.md` | clôture chez Claude Code, drainer la mémoire automatique |
| `references/CONVENTION.md` | spécification des trois piliers et propriétaire de chaque savoir |
| `references/CONFIG-PROJET.md` | chaque clé du bloc `contexte:convention`, défaut et exemple |
| `references/BUDGET.md` | seuils, geste par fichier qui déborde, `CLAUDE.md` sans audit |
| `references/ZONES.md` | un répertoire mérite sa carte |
| `references/DOCS-SYSTEM.md` | organisation de `docs/`, ADR, index |
| `references/ARCHIVAGE.md` | archiver, corriger ou supprimer, rotation des journaux |
| `references/PROFILS-PROJETS.md` | adapter la convention au type de projet |
| `references/HANDOFF.md` | test « prêt pour un contexte neuf » |
| `references/RESOLUTION.md` | la boucle `$SKILL` rend vide ou la mauvaise version |
| `references/plan/PLAN.md` | rédiger un plan, ossature et format d'une tâche |
| `references/plan/PROMPT.md` | rédiger le prompt d'exécution |
| `references/plan/RECHERCHE.md` | phase de recherche d'un plan |
| `references/plan/TYPES-DE-PLAN.md` | triage, sections propres à chaque type |
| `references/audit-md/les-quatre-etages.md` | choisir où sort un bloc de `CLAUDE.md` |
| `references/audit-md/criteres-classement.md` | trancher un cas limite de classement |
| `references/audit-md/anti-patterns.md` | justifier une suppression |
| `references/audit-md/modeles.md` | gabarit de fichier racine et de fiche |
| `references/audit-md/fichiers-agents.md` | le dépôt déclare des sous-agents |
| `templates/` | gabarits des piliers, zones, ADR et du plan |

## Scripts

Tous s'appellent par `bash "$SKILL/scripts/<nom>"`.

| Script | Rôle |
|---|---|
| `ctx-init.sh` | détecte le terrain, crée ce qui manque sans rien écraser |
| `ctx-audit.sh` | mesure les surfaces et contrôle la convention |
| `ctx-rotation.sh` | fait tourner les journaux |
| `ctx-archive.sh` | déplace un fichier vers `archives/` avec son en-tête |
| `ctx-archeo.sh` | seule porte de lecture de `archives/` |
| `ctx-migrer.sh` | simule puis applique le passage en version 5 |
| `ctx-verite.sh` | confronte la doc au code |
| `ctx-demarrage.sh` | témoin de reprise, appelé par le hook de démarrage |
| `ctx-commun.sh` | fonctions partagées, ne s'appelle pas seul |
| `verif-refs.sh`, `verif-agents.sh` | références mortes, déclarations d'agents |
