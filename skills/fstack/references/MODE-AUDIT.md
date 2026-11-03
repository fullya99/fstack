# Mode AUDIT

> **Le contrat** : un fichier racine court, où chaque ligne restante est vraie et prouvée, et tout
> le reste rangé là où ça ne coûte rien tant que ça ne sert pas. Rien n'est écrit avant que
> l'opérateur ait lu le rapport et dit oui.

Un fichier d'instructions est chargé en entier à chaque session, donc chaque ligne se paie pour
toujours, et au-delà de 200 lignes la doc annonce une baisse d'obéissance. Ce mode raccourcit, et
la vérification contre le code rend chaque coupe défendable.

Charge `style-redaction` avant d'écrire. S'il manque, applique la langue déclarée par le bloc
`contexte:convention`, un ton direct et aucune tournure qui sent le texte généré.

## Ce que le mode traite

Six phases pour un allègement ou un audit. « Vérifie juste si c'est vrai » s'arrête après la phase
2. Un bloc précis à sortir passe par les phases 3 et 5. Ajouter une règle ou écrire un fichier de
zéro est hors périmètre : le mode déplace et supprime, il n'invente pas.

## Les lecteurs

Claude Code lit `CLAUDE.md`, `.claude/CLAUDE.md`, `CLAUDE.local.md`, les `CLAUDE.md` imbriqués,
`.claude/rules/*.md` et `.claude/agents/*.md`. Codex, Hermes Agent et OpenClaw lisent `AGENTS.md`
(Hermes lit aussi `CLAUDE.md`), Cursor, Windsurf et Cline leurs propres fichiers de règles.

**Claude Code ne lit pas `AGENTS.md`.** Un dépôt qui porte les deux fichiers fait tourner deux
sources qui divergent sans que rien le dise. Le raccord est une ligne `@AGENTS.md` en tête du
`CLAUDE.md`, ou un lien symbolique. Deux fichiers sans raccord se constatent en phase 2.

Tout ce qui vit hors du dépôt (`~/.claude/`, `~/.agents/`, `~/.codex/`, `~/.hermes/`, la politique
gérée) se signale dans l'inventaire sans y toucher. Aucune instruction n'est universelle : `/clear`,
`/compact`, un identifiant de modèle ou un nom de sous-agent sont des cas Claude Code, et une règle
qui en parle se range en disant pour quel lecteur elle vaut.

### Les imports et les règles

Chez Claude Code, une ligne `@chemin/fichier` hors d'un bloc de code charge ce fichier au
démarrage, jusqu'à quatre sauts. Un import mort est une ligne morte silencieuse, et un fichier
importé compte dans le budget comme s'il était collé dans la racine. Un `@docs/guide.md` cité en
exemple en charge un vraiment.

Claude Code ne lit que `paths:` dans le frontmatter d'une règle. Une règle en `globs:` ne se charge
pas à la demande, `ctx-audit.sh` la signale. La correction est `globs:` vers `paths:`, avec le diff.

## Avant de commencer

L'argument de la commande, s'il est donné, est le fichier ou le dossier à auditer en priorité.

**L'arbre git doit être propre**, pour pouvoir tout annuler d'un `git checkout`.

```bash
git status --porcelain
```

Si ça sort quelque chose, demande de commiter d'abord. Pas de `.bak`, pas de stash décidé seul.

**La convention de rangement du projet gagne.** `ls -1 docs/ archives/ CODEMAP.md TODOS.md 2>/dev/null`
dit ce qui existe, le bloc `contexte:convention` dit ce qui est déclaré. Tu ranges là. Si rien
n'existe, tu proposes `docs/` et `archives/` et tu attends la confirmation. Jamais d'arborescence
parallèle sous `.claude/`.

## Les six phases

### Phase 1. Inventaire

```bash
find . -path ./node_modules -prune -o \( -name 'CLAUDE*.md' -o -name 'AGENTS.md' \
  -o -path '*/.claude/rules/*.md' -o -path '*/.claude/agents/*.md' \) -print
grep -nE '^[[:space:]]*@[^[:space:]`]+' CLAUDE.md 2>/dev/null   # les imports
wc -l CLAUDE.md AGENTS.md 2>/dev/null
git log -1 --format=%ad --date=short -- CLAUDE.md
grep -nE '^[[:space:]]*@[^[:space:]`]+' CLAUDE.md 2>/dev/null   # les imports
```

Relève pour chaque fichier la taille, la date du dernier commit et la portée de chargement. Un
fichier importé compte dans le total de la racine. Relève aussi les documents existants (`docs/`,
`CODEMAP.md`, ADR) : une ligne dont le contenu y figure devient un lien, pas une fiche.
Observable : un tableau fichier, lignes, date, portée.

### Phase 2. Vérification contre le code

Deux passes mécaniques, puis ton jugement. `$SKILL` se résout comme décrit dans `SKILL.md`.

```bash
bash "$SKILL/scripts/verif-refs.sh" --format=md CLAUDE.md AGENTS.md
bash "$SKILL/scripts/ctx-verite.sh" --info
```

`verif-refs.sh` donne un verdict par chemin, commande, glob ou import cité. `ctx-verite.sh` couvre
en plus `docs/` et les piliers, et vérifie les options `--x` des scripts du dépôt, les commandes
`npm run`, `bun run`, `make` contre le manifeste et les comptages « N fichiers » devant un
répertoire. Chez Claude Code, confie la seconde au profil `fstack:controleur`, qui rend la
sortie telle quelle. Ailleurs, lance-la toi-même.

`ctx-verite.sh` gradue ses sorties. Le niveau `alerte` est une affirmation fausse prouvée par le
dépôt, il bloque `--strict` et va au tableau des preuves. Le niveau `info` est un chemin cité au fil
de la phrase ou un nom seul, affiché par `--info` seulement, jamais bloquant. Un `info` n'est pas un
faux : sur trois clones ces mentions étaient fausses dans 87 % des cas, tu les relis et tu tranches.

Ce que les scripts laissent à ta charge : une dépendance ou une version (tu lis le manifeste et tu
compares la valeur), un `paths:` de règle (il doit matcher au moins un fichier), une convention de
code ou de nommage (tu comptes, « 3 fichiers sur 40 » est la preuve), une règle d'organisation (un
grep qui la contredirait, rien en sortie la confirme), et les `info`.

Trois verdicts, un seul par affirmation. `VRAI` : le dépôt confirme. `FAUX` : le dépôt contredit
et tu tiens une preuve que l'opérateur peut relancer, le chemin absent, la ligne du manifeste, le
comptage. `NON VÉRIFIABLE` : tu n'as pas de quoi trancher, c'est honnête, et l'affirmation reste
où elle est. Une convention suivie à 90 % est vraie. À 8 % elle est fausse, le comptage le prouve.
Entre les deux, tu poses la question en phase 4.

Les motifs déclarés par `exceptions: verite=<motif>` dans le bloc sont déjà tranchés, ne les relève pas.

### Les fichiers d'agents

Un fichier d'agent mal formé n'est pas chargé, sans erreur ni avertissement.

```bash
bash "$SKILL/scripts/verif-agents.sh" .claude/agents/
```

Le script couvre les façons de disparaître sans bruit, la table des clés est dans
`references/audit-md/fichiers-agents.md`.

**Le modèle se pose par alias** (`haiku`, `sonnet`, `opus`), jamais par identifiant daté. Un
identifiant figé ne suit pas la dernière version de sa famille, et un agent sans `model` hérite du
modèle de la session, souvent le plus cher. `ctx-audit.sh` le signale (contrôle de l'identifiant de modèle figé ou de l'agent sans `model:`). Tu proposes
l'alias, avec le diff, et seul le frontmatter bouge.

**Les profils locaux.** Chez Claude Code, relis les agents de `.claude/agents/` et compare chacun
aux profils du plugin. Un agent local qui refait `explorateur`, `controleur`, `executant`,
`developpeur`, `chercheur`, `expert` ou `relecteur` se propose au remplacement par
`fstack:<profil>`, avec la justification et le diff de suppression. Un agent qui porte un
rôle propre au projet reste. La doctrine est dans `DELEGATION.md`.

Reste à lire : la `description` doit déclencher (trois mots ne déclenchent jamais), deux
descriptions proches se marchent dessus (question en phase 4), et le corps ne doit pas redire le
`CLAUDE.md`. **Tu ne réécris jamais le corps d'un agent.** Le frontmatter se corrige, le prompt
est un choix de son auteur.

### Phase 3. Classement, bloc par bloc

Un bloc est une règle : une puce, un paragraphe, une section courte. Il reçoit une étiquette.

| Étiquette | Critère | Destination |
|---|---|---|
| `RACINE` | vrai partout, tout le temps | reste dans le fichier racine |
| `SORTIR` | vrai, mais ne sert que pour une tâche, un dossier ou un module | un des trois étages du bas |
| `ARCHIVE` | était vrai, garde une valeur de trace | `archives/`, avec sa date et la raison |
| `SUPPRIMER` | faux sans rien à garder, ou vide de sens | supprimé, listé avec la preuve |

`SORTIR` demande un second choix, l'étage.

| Étage | Où | Quand ça charge |
|---|---|---|
| Lien simple | une ligne de la table de renvoi | si l'agent ouvre le lien |
| Règle à `paths` | `.claude/rules/<sujet>.md` avec `paths:` | seule, quand un fichier qui matche est touché |
| Carte de zone | `CODEMAP.md` ou la carte d'un sous-dossier | quand on travaille dans la zone |
| Fiche | `docs/<sujet>.md`, liée depuis la racine | si l'agent ouvre le lien |

Une procédure qui se rejoue part en skill. **Une contrainte qui doit être appliquée ne va jamais
dans une fiche**, un lien nu ne garantit rien : règle à `paths` si elle est propre à un dossier,
sinon elle reste à la racine, même si ça l'allonge. Détail dans
`references/audit-md/les-quatre-etages.md`, cas limites dans
`references/audit-md/criteres-classement.md`.

Va en `SUPPRIMER` ce que l'agent fait déjà par défaut, ce qu'un linter applique, ce qui est trop
vague pour se suivre. La liste complète est dans `references/audit-md/anti-patterns.md`. Une règle
fausse qui redevient vraie en corrigeant une valeur se corrige, elle ne se supprime pas.

Observable : chaque bloc porte une étiquette, et chaque `SORTIR` un étage.

### Phase 4. Contradictions

Liste les règles qui s'opposent, y compris `CLAUDE.md` contre `AGENTS.md` ou un fichier imbriqué
contre la racine. Pour chacune tu montres les deux versions, leur emplacement et leur date, et **tu
poses la question à l'opérateur**. Tu ne tranches jamais. Une contradiction ouverte bloque le
classement de ses deux blocs, pas le reste.

### Phase 5. Restructuration

La racine vise **100 lignes**, alerte à **150**, blocage à **200** (seuils de `references/BUDGET.md`), sauf seuil déclaré dans le bloc `contexte:convention`. Elle porte le projet en deux
phrases, les commandes réelles, les contraintes sans exception et la table de renvoi. Chaque ligne
de la table dit la situation avant le chemin (« Tu ajoutes une migration », puis
`docs/migrations.md`), sinon elle ne se fait pas ouvrir.

Une fiche dit quand elle s'applique et traite un seul sujet, de 15 à 150 lignes. Une règle à
`paths` porte un glob qui matche au moins un fichier. **Aucun `@import` pour alléger**, il charge
au démarrage. Les gabarits sont dans `references/audit-md/modeles.md`.

**Tu ne casses pas les liens.** Après un déplacement, repasse sur le dépôt.

```bash
grep -rn "CLAUDE.md" --include='*.md' --include='*.yml' --include='*.yaml' . | grep -v node_modules
bash "$SKILL/scripts/verif-refs.sh" CLAUDE.md
bash "$SKILL/scripts/ctx-verite.sh" --strict
```

Observable : `verif-refs.sh` et `ctx-verite.sh --strict` sortent à 0.

### Phase 6. Rapport, puis validation

Tu présentes le plan complet **avant d'écrire**, en quatre morceaux dans cet ordre.

1. Le tableau des vérifications, un verdict et une preuve par affirmation.
2. Le diff du fichier racine, lignes avant et après, gain en pourcentage.
3. Ce qui sort, avec l'étage et le nombre de lignes de chaque morceau.
4. Les suppressions, une ligne par bloc avec la preuve.

Les propositions sur les agents (alias, remplacement par un profil) et les `globs:` à convertir
viennent avec leur diff. L'opérateur approuve, corrige ou refuse bloc par bloc, tu n'écris
qu'après. Relance ensuite l'audit : un second passage ne doit rien changer, sinon la phase 3 a mal
classé.

## Invariants

- Aucune écriture avant validation du rapport, aucun travail sur un arbre git sale.
- Aucun `FAUX` sans preuve relançable, aucune contradiction tranchée sans l'opérateur.
- Aucune invention : tu déplaces, tu supprimes, tu corriges une valeur fausse par la vraie.
- Aucun lien cassé, aucune arborescence parallèle, aucune modification hors du dépôt.
- Aucune réécriture du corps d'un agent, aucun `@import` pour alléger.

## Références

| Fichier | Quand le lire |
|---|---|
| `references/audit-md/les-quatre-etages.md` | phases 3 et 5, choisir l'étage d'un bloc |
| `references/audit-md/criteres-classement.md` | phase 3, `SORTIR` contre `ARCHIVE`, cas limites |
| `references/audit-md/anti-patterns.md` | phase 3, justifier un `SUPPRIMER` |
| `references/audit-md/modeles.md` | phase 5, gabarits de la racine et d'une fiche |
| `references/audit-md/fichiers-agents.md` | phase 2, dépôt qui déclare des sous-agents |
