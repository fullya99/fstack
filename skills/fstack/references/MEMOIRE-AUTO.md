# MEMOIRE-AUTO : la mémoire automatique de Claude Code et son drainage

> La mémoire automatique est un carnet que Claude Code tient seul. Il se remplit de faits qui
> ont un propriétaire dans la convention. La clôture le vide vers ces propriétaires.

## Où elle vit et comment elle se charge

```bash
ls ~/.claude/projects/<chemin du projet>/memory/
```

Le nom du dossier est le chemin absolu du projet où chaque caractère non alphanumérique devient
un tiret, par exemple `-home-ana-code-mon-app`. Une copie du dépôt ailleurs sur la machine a donc
sa propre mémoire.

| Fait | Conséquence |
|---|---|
| `MEMORY.md` est l'index, chargé sur ses 200 premières lignes ou 25 Ko | le reste de l'index est invisible |
| Les fichiers thématiques liés depuis l'index se lisent à la demande | ils ne coûtent rien tant qu'on ne les ouvre pas |
| Les sous-agents ne la chargent pas | un fait qui n'y vit que là manque à tout agent délégué |
| Elle est propre à la machine | elle ne passe pas dans un clone et ne se relit pas en revue |

Source : code.claude.com/docs/en/memory, consultée le 2026-10-11. Les fichiers sont des
markdown ordinaires, on les édite à la main. Les autres plateformes (Codex, Hermes, OpenClaw,
Claude web) ont leur propre mémoire, ailleurs et sous d'autres règles, ce skill ne la traite pas.

## Le drainage, à chaque clôture

Lister d'abord ce qui existe.

```bash
M=~/.claude/projects/$(pwd | sed 's/[^A-Za-z0-9]/-/g')/memory
wc -l "$M/MEMORY.md" && ls "$M"
```

Absent, il n'y a rien à drainer, la phase se clôt en une ligne. Sinon, chaque entrée reçoit un
seul sort, selon la grille de l'ADR du projet ou, à défaut, celle-ci.

| Ce que dit l'entrée | Où elle va |
|---|---|
| Décision et son pourquoi | `docs/decisions/ADR-NNNN-*.md` |
| Piège d'un module | la fiche `docs/modules/<module>.md`, ou la carte de sa zone |
| Piège sans module | `docs/pieges/` si le projet en a un, sinon la section zones sensibles de `CODEMAP.md`, jamais les deux dans un même projet |
| Préférence durable de l'opérateur sur le projet | `CLAUDE.md`, si le budget le permet |
| Contrainte d'environnement, accès, outil | `CODEMAP.md`, section dépendances |
| Fait externe daté | `docs/veille/` ou une entrée du journal |
| Recopie de ce qui existe déjà | supprimée |
| Propre à la machine ou à l'opérateur, pas au projet | reste en mémoire |

Une entrée promue se retire de l'index et son fichier se supprime. Observable : après la phase,
chaque entrée supprimée ou promue a une trace dans le diff, et `MEMORY.md` ne liste plus que
des entrées qui n'ont pas de propriétaire dans le dépôt (chemins locaux, préférences de poste,
identité git).

## Ce que l'audit mesure

`bash "$SKILL/scripts/ctx-audit.sh"` lit l'index de ce projet, section 11.

- Index au-dessus de 150 lignes : alerte. Le seuil se règle par la clé `memoire-auto` du bloc.
- Entrée qui recopie `CLAUDE.md` : alerte, une phrase de 50 caractères ou plus, identique après
  mise en minuscules et retrait de la ponctuation.
- Mémoire absente : rien n'est dit.

## Un `MEMORY.md` commité à la racine

Les projets des anciennes versions de la convention ont un `MEMORY.md` dans le dépôt, qui jouait
le rôle de quatrième pilier. L'audit le signale. Le skill ne le dissout jamais en silence.

1. Un projet qui s'en sert volontairement le déclare dans la ligne `ecarts:` du bloc
   `contexte:convention`, par une entrée `MEMORY.md=<justification>`. L'alerte de l'audit devient
   alors une information qui cite la justification. Sans l'entrée, l'alerte reste.
2. Sinon, `/fstack:migrer` propose de répartir son contenu selon la grille ci-dessus, sur une
   branche. L'opérateur tranche à la relecture de la PR.

Pas de dissolution hors d'une branche, pas de suppression avant que chaque ligne ait un nouveau
propriétaire ou une raison écrite de disparaître. Le mode qui porte la phase est décrit dans
`MODE-CLOTURE.md`, la migration dans `MODE-MIGRER.md`.
