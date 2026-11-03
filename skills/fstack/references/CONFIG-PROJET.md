# CONFIG-PROJET : le bloc `contexte:convention`

> Tout ce qui varie d'un projet à l'autre se déclare dans ce bloc, jamais dans un script recopié.
> Un projet ne forke plus un script, il règle une ligne.

Le bloc ouvre `CODEMAP.md`. Les scripts le cherchent d'abord là, puis dans `CLAUDE.md`,
`AGENTS.md`, puis les autres `.md` de la racine. Une ligne par clé, `clé: valeur`, listes séparées
par des virgules. Seule `version` est obligatoire.

```
<!-- contexte:convention
version: 5
profil: application
piliers: CODEMAP.md, TODOS.md, CHANGELOG.md
docs: docs/
archives: archives/
langue: fr
journal: date-titre
seuils: CODEMAP.md=600, CLAUDE.md=250
ajourne: CLAUDE.md=411@2026-09-07
taille-forcee: moyenne
ignorer: projets/*/context-input/**, legacy/old.sh
exceptions: secret=tests/test_web_sante.py, lien=machines/**
ecarts: MEMORY.md=pilier assumé, voir docs/decisions/ADR-0002
-->
```

| Clé | Défaut | Rôle |
|---|---|---|
| `version` | 4 si la ligne manque | Version du bloc. Un script plus ancien refuse de tourner et le dit. |
| `profil` | déduit par `ctx-init.sh` | Type de projet, voir `PROFILS-PROJETS.md`. |
| `piliers` | `CODEMAP.md, TODOS.md, CHANGELOG.md` | Les trois piliers. |
| `docs` | `docs/` | Répertoire des fiches. |
| `archives` | `archives/` | Répertoire des archives. |
| `plans` | `plans/` | Répertoire des plans. `plans: docs/plans/` pour un dépôt qui les range ailleurs. Sert à `ctx-rotation.sh --plans` et au contrôle des plans exécutés de l'audit. |
| `langue` | `fr` | Langue de la prose. |
| `journal` | essaie les trois | `date-titre` (`## AAAA-MM-JJ`), `keep-a-changelog` (`## [x] - AAAA-MM-JJ`) ou `crochets` (`[AAAA-MM-JJ] [TYPE]`). |
| `seuils` | ceux de `BUDGET.md` | `fichier=lignes`, un par fichier à relever. |
| `taille-forcee` | aucune | Impose `petite`, `moyenne` ou `grande` à la place de la mesure. |
| `ajourne` | aucun | Dépassement gelé, `fichier=lignes@date`. Il ne doit plus grossir. |
| `ignorer` | aucun | Globs relatifs à la racine que les scripts ne parcourent pas, voir `ignorer` plus bas. |
| `exceptions` | aucune | `type=motif`, motif en glob shell, `**` compris. Jugements déjà rendus. |
| `ecarts` | aucun | Écart assumé à la convention, avec sa justification. |

## `ignorer`

Les scripts parcourent tout ce que le disque porte, **gitignoré compris** : une note locale, un
`context-input/` ignoré, un livrable ou un `CLAUDE.local.md` sont du contexte. Seul le généré lourd
s'élague, reconnu à sa nature et jamais d'après le `.gitignore` :

- une liste fixe : `node_modules`, `vendor`, `.venv`, `venv`, `dist`, `build`, `target`, `.next`,
  `__pycache__`, `.cache`, `.gradle`, `Pods`, `.dart_tool`, `.nuxt`, `.svelte-kit`, `.turbo`,
  `.parcel-cache`, `.terraform`, `.pytest_cache`, `.mypy_cache`, `.tox`.
- tout dossier qui porte un `CACHEDIR.TAG` dont la première ligne est la signature du standard
  (`Signature: 8a477f597d28d172789f06886806bc55`), Cargo en pose un dans `target/`.
- les dossiers d'un moteur de jeu, **seulement si son marqueur existe**, à la racine ou jusqu'à la
  profondeur 3 (`game/`, `clients/godot/`) : Unity (`Library`, `Temp`, `Logs`, `obj`,
  `UserSettings` si `ProjectSettings/ProjectVersion.txt` existe), Unreal (`Intermediate`,
  `Binaries`, `DerivedDataCache`, `Saved` si un `*.uproject` existe), Godot (`.godot` si
  `project.godot` existe). Un plugin Unreal (`Plugins/*/*.uplugin`, profondeur 5) élague son
  `Intermediate` et son `Binaries`. Les dossiers se lisent depuis la racine du moteur, jamais par
  leur nom seul : un `Library/` de projet ordinaire, même à côté d'un `game/` Unity, reste
  parcouru. Au plus 20 racines de moteur, l'audit dit combien dépassent. Un moteur plus profond se
  couvre avec `ignorer:`.

`ignorer:` couvre le dernier cas : ce que git suit mais qui ne fait pas partie du projet, un ancien
dépôt importé tel quel. Ce sont des globs relatifs à la racine, séparés par des virgules :
`ignorer: projets/*/context-input/**, legacy/old.sh`. Un glob qui finit par `/**`, `/*` ou `/` saute
le contenu du dossier, `**/x` vaut `x` à toute profondeur, tout autre glob saute le chemin visé. Un
glob qui contient une espace est ignoré. Ces fichiers ne comptent ni dans la taille du projet ni
dans les contrôles de l'audit, de `ctx-verite.sh`, de `ctx-init.sh` et de `ctx-migrer.sh`.

Un élagage se nomme toujours : la section 10 de l'audit dit en une ligne ce que `ignorer:` a fait
sauter, avec le nombre de fichiers, ce que chaque moteur reconnu a élagué et les dossiers élagués
par `CACHEDIR.TAG`. `ctx-init.sh` le dit après la taille. En section 1, l'audit annonce aussi, en
information, les fichiers `.md` que git ignore (hors dossiers élagués) : ils restent du contexte
pour les scripts, mais ils ne voyagent ni vers un collègue ni vers une autre machine.

## `taille-forcee`

L'audit mesure la taille du projet (moins de 150 fichiers hors dépendances : `petite`, 150 à 600 :
`moyenne`, au-delà : `grande`). `taille-forcee:` l'impose et les contrôles suivent la valeur forcée.
Quand elle diffère de la mesure, l'audit le dit en information. Une valeur hors des trois est
ignorée, la mesure est gardée.

La migration la pose quand une ancienne ligne `taille:` diffère de la mesure. Elle la note à
confirmer. Si la mesure convient, on retire la ligne. Une ligne `taille:` n'est plus lue depuis la
version 5, l'audit demande de la retirer ou de la passer en `taille-forcee:`.

## `seuils`

`fichier=N` fixe le seuil d'**alerte**. Le blocage suit dans le même rapport que les valeurs par
défaut, arrondi à l'entier : `CODEMAP.md=600` donne une alerte à 600 et un blocage à 800, comme 300
et 400 par défaut. Une valeur non numérique est ignorée.

Clés admises en plus des chemins de fichier :

| Clé | Surface | Défaut alerte / blocage |
|---|---|---|
| `reprise` | bloc de reprise de TODOS | 50 / 80 |
| `cout-reprise` | somme de ce qu'une session charge au départ | 600 / 900 |
| `regles-sans-paths` | règles `.claude/rules/` sans `paths` | 150 / 200 |
| `memoire-auto` | index de la mémoire automatique | 150 / aucun, hors dépôt |
| `ligne` | longueur d'une ligne, en caractères, dans les fichiers d'état | 800 / aucun, une alerte par fichier |
| `car-CODEMAP.md` | poids du CODEMAP racine, en caractères | 30 000 / 40 000 |
| `car-<zone>/CODEMAP.md` | poids d'une carte de zone, en caractères | 20 000 / 25 000 |
| `car-TODOS.md` | poids de TODOS, en caractères | 20 000 / 30 000 |
| `car-cout-reprise` | somme de ce qu'une session charge au départ, en caractères | 60 000 / 90 000 |

Les clés `car-` se lisent comme les autres : la valeur fixe l'alerte, le blocage suit dans le même
rapport. Elles ne dépendent pas du seuil en lignes du même fichier, relever `CODEMAP.md=600` ne
relève pas `car-CODEMAP.md`. Les caractères se comptent sans les octets de continuation UTF-8.

## `ajourne`

Cliquet sur un dépassement déjà là, `fichier=lignes@AAAA-MM-JJ`, entrées séparées par des virgules.
Tant que le fichier ne dépasse pas la valeur gelée, l'alerte ou le blocage ne se dit plus et l'audit
rappelle l'entrée en information. S'il grossit au-delà, c'est un **blocage**. Dès qu'il repasse sous
son seuil d'alerte, l'audit alerte : « retirer l'entrée ». Une entrée illisible ou dont le fichier
n'existe plus donne aussi une alerte.

## `exceptions`

`type=motif`, motif en glob shell, `*` et `**` couvrent aussi les `/`. Un jugement déjà rendu, pas
une désactivation du contrôle.

| Type | Ce qu'il fait taire | Le motif vise | Exemple |
|---|---|---|---|
| `fiche` | fiche de `docs/` absente de l'index | le chemin de la fiche | `fiche=docs/brouillons/**` |
| `lien` | lien mort ou cible introuvable | la cible telle qu'écrite, depuis la racine, ou la page qui porte le lien | `lien=machines/**` |
| `archive` | archive sans en-tête ou hors index | le chemin de l'archive | `archive=archives/2025-*` |
| `secret` | valeur suspecte d'un secret | le fichier qui la porte | `secret=tests/test_web_sante.py` |
| `agent` | agent sans `model:` ou avec un identifiant complet | le chemin de l'agent | `agent=.claude/agents/ancien.md` |
| `verite` | affirmation du texte que `ctx-verite.sh` ne retrouve pas (chemin, script, option, commande, comptage) | l'affirmation telle qu'écrite | `verite=scripts/ancien.sh` |

`ctx-verite.sh` lit aussi `lien` : un motif `lien` couvre les mêmes affirmations qu'un motif
`verite`. Pour un comptage, le motif est le répertoire, avec ou sans `/` final.

Les sous-modules ne se déclarent pas, ils se lisent dans `.gitmodules`.
