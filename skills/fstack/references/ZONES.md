# ZONES : découper la carte sans découper l'état

> Une zone donne sa propre carte à un répertoire trop gros pour tenir dans le CODEMAP racine.
> L'état et le journal restent uniques, une zone n'a jamais de TODOS ni de CHANGELOG à elle.

## Ce qu'est une zone, et ce qu'elle n'est pas

Une zone est un répertoire qui porte `CODEMAP.md`, et au besoin `CLAUDE.md`. Rien d'autre. Elle
se distingue d'un niveau autonome, qui porte les trois piliers et se clôture à part, cas d'un
package de monorepo ou d'un sous-projet livré séparément.

| | Zone | Niveau autonome | Fiche `docs/modules/` |
|---|---|---|---|
| Ce que ça porte | `CODEMAP.md`, `CLAUDE.md` facultatif | les 3 piliers complets | une page de connaissance |
| Se clôture | dans la clôture du parent | à part, le parent pointe | mise à jour en phase 3 |
| Quand on le choisit | un répertoire de code trop gros pour le CODEMAP racine | un sous-projet qui a sa propre vie | un sujet qui mérite d'être expliqué, pas rangé |

`ctx-audit.sh` distingue niveau et zone par la présence des trois piliers : un `CODEMAP.md` seul
est une zone, les trois ensemble sont un niveau, section 1b de l'audit.

## Quand créer une zone

Un répertoire est candidat s'il porte au moins 25 fichiers, ou s'il occupe plus de 30 lignes du
CODEMAP racine, ou s'il a sa propre fiche `docs/modules/` de plus de 100 lignes. Le script
propose, `ctx-audit.sh --budget` liste les candidats, le skill décide.

Une zone par sujet qu'on a en tête en même temps. Jamais une zone de dix lignes recousue pour
faire un chiffre, ces lignes restent au CODEMAP racine ou rejoignent une zone voisine.

Selon la taille du projet : petit, aucune zone. Moyen, une zone là où le CODEMAP racine déborde,
pas avant. Grand, des zones dès l'INIT, le CODEMAP racine naît comme un index.

## Ce que porte une zone

**`<zone>/CODEMAP.md`**, obligatoire, gabarit `templates/CODEMAP-zone.md`. Rôle en une phrase,
arborescence de la zone, points d'entrée, flux, pièges. C'est ici que vont les zones sensibles qui
concernent la zone, plus dans le CODEMAP racine. Cible 150 lignes.

**`<zone>/CLAUDE.md`**, facultatif, gabarit `templates/CLAUDE-zone.md`, 30 lignes au plus.
Seulement les règles qui doivent tenir quand on édite dans la zone, formulées comme des faits sur
la zone.

```bash
bash "$SKILL/scripts/ctx-init.sh" --zone src/<dir>                 # pose la carte
bash "$SKILL/scripts/ctx-init.sh" --zone src/<dir> --with-claude   # pose la carte et les règles
```

## Ce qui reste à la racine

Les interdits sans exception, la sécurité, ce qui vaut partout, jamais seulement dans une zone.
Un agent qui travaille ailleurs dans le dépôt ne verrait pas une règle de zone, c'est le piège de
la feuille paresseuse : une contrainte qui doit tenir partout et qu'on n'a écrite que dans
`<zone>/CLAUDE.md` n'existe pour personne d'autre.

Le piège de précédence, documenté sur un cas réel (Knack, 2026-05-22,
https://getknack.ai/blog/agents-md-monorepo) : une règle racine disait « toujours lancer la suite
complète », une règle de service disait « ce service filtre ses tests ». La règle de service était
plus proche et aurait dû l'emporter sur le papier, le modèle a suivi la racine parce qu'elle était
formulée à l'impératif. Conséquence pour l'écriture : la racine ne porte pas d'impératif qui
contredit une zone, et une zone formule ses règles comme des faits sur elle-même, jamais comme des
ordres généraux.

## Ce que chaque lecteur charge

Pour `<zone>/CLAUDE.md` :

| Lecteur | Comportement |
|---|---|
| Claude Code | à la demande, quand un fichier de la zone est lu, jamais avant (doc officielle, memory.md) |
| Codex | `AGENTS.md` au même endroit, fusionné racine vers cwd, 32 Kio cumulés pour tous les fichiers du chemin |
| Hermes | rien ne le charge |
| OpenClaw | rien ne le charge |

Pour `<zone>/CODEMAP.md` : tout le monde, à la demande, c'est un fichier `.md` ordinaire, aucun
mécanisme spécial ne le charge ni ne le bloque.

Conséquence directe : la carte est la partie portable de la zone, elle voyage sur tous les
lecteurs. Les règles de zone sont un confort propre à Claude Code et Codex, pas une garantie.
Une contrainte qui doit tenir sur tous les lecteurs va à la racine, jamais seulement en
`<zone>/CLAUDE.md`.

## Le CODEMAP racine après découpe

Il devient un index. Une table « Zones » qui pointe, sans recopier :

| Zone | Rôle | Carte |
|---|---|---|
| `src/api` | expose les routes HTTP | `src/api/CODEMAP.md` |

Plus une arborescence d'un niveau, les points d'entrée globaux, le flux global et les zones
sensibles qui ne relèvent d'aucune zone. Une zone sensible qui concerne une zone précise vit dans
sa carte, pas ici.

## Maintenance

À chaque clôture, la carte de chaque zone touchée se met à jour dans la même passe que les trois
piliers. Une zone qui dépasse 250 lignes se scinde en deux. Une zone dont le répertoire disparaît
part en archive par `$SKILL/scripts/ctx-archive.sh`, jamais à la main, et la table « Zones » du
CODEMAP racine perd sa ligne dans le même mouvement.
