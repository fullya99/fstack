# BUDGET : ce qui déborde descend d'un étage

> Chaque surface de la convention a une cible, une alerte, un blocage. Le budget est un invariant,
> au même rang que le vrai : un fichier juste mais trop long pour être lu est une doc perdue.

## Pourquoi un budget

Cas mesuré, un projet réel de 979 fichiers, 549 commits, 83 clôtures en 17 jours.

| Pilier | Lignes | Ce qui a dérivé |
|---|---|---|
| `CLAUDE.md` | 647 | un paragraphe d'état de 70 lignes, 99 règles avec leur récit |
| `CODEMAP.md` | 2 567 | zones sensibles 1 388 lignes, commandes 513 lignes avec des récits dans les commentaires |
| `TODOS.md` | 6 534 | bloc de reprise de 2 579 lignes, 9 sections « ce que cette session a produit », 73 cases cochées |
| `CHANGELOG.md` | 8 283 | 148 entrées, jusqu'à 153 lignes chacune |

`ctx-audit.sh` rendait 11 alertes mineures sur ce projet, aucune sur la taille. Trois causes.

1. Aucun seuil, donc aucune porte. « Vise court » restait un conseil.
2. « Aucune suppression silencieuse » se lisait comme « aucun retrait ». Le bloc de reprise
   devenait un journal, TODOS absorbait des comptes-rendus de session, CLAUDE.md absorbait l'état.
3. Un seul niveau de doc pour un projet à quinze modules. Les pièges de module retombaient dans
   les zones sensibles du CODEMAP racine et dans CLAUDE.md, faute de propriétaire plus proche.

Le point de recherche qui compte, et pourquoi on classe avant de retirer. Au-delà d'un certain
volume d'instructions, le modèle ne se met pas à ignorer seulement la dernière règle ajoutée, il
suit l'ensemble des règles moins bien, de façon uniforme (HumanLayer, 2025-11-25,
https://www.humanlayer.com/blog/writing-a-good-claude-md). Et un résumé uniforme d'un journal
perd les contraintes qu'il porte, 53 % de rappel après une passe de compaction, 10 % après cinq
(« The Compaction Cliff in Long-Running AI Agent Memory », arxiv 2608.22752). Les deux mènent à la
même règle : on ne retire jamais en bloc, on classe d'abord chaque phrase par ce qu'elle est, et
chacune part chez son propriétaire.

Le seuil chiffré n'est qu'un détecteur, pas la règle elle-même. Le critère de découpe reste
sémantique, un fichier répond à une question, c'est ce que disent Diátaxis et DITA, qui ne fixent
aucune longueur maximale (diataxis.fr, https://diataxis.fr/start-here/). Le seul guide de style à
publier une règle chiffrée de découpe est GitLab, plus de cinq niveaux de titres veut dire
plusieurs sujets (docs.gitlab.com, https://docs.gitlab.com/development/documentation/styleguide/).
Le nombre dit d'aller regarder, ce qu'on trouve dit quel geste prendre.

## Les seuils

| Surface | Cible | Alerte | Blocage |
|---|---|---|---|
| `CLAUDE.md` racine | ≤ 100 lignes | 150 | 200 lignes, ou 40 000 caractères |
| `CLAUDE.md` de zone | ≤ 30 | 40 | 60 |
| `CODEMAP.md` racine | ≤ 250 | 300 lignes, ou 30 000 caractères | 400 lignes, ou 40 000 caractères |
| `CODEMAP.md` de zone | ≤ 150 | 200 lignes, ou 20 000 caractères | 250 lignes, ou 25 000 caractères |
| `TODOS.md` | ≤ 150 | 200 lignes, ou 20 000 caractères | 300 lignes, ou 30 000 caractères |
| bloc « État à la reprise » | ≤ 40 | 50 | 80 |
| `CHANGELOG.md` | ≤ 30 entrées | 40 entrées ou 1 000 lignes | 60 entrées ou 1 500 lignes |
| une entrée de CHANGELOG | ≤ 25 lignes | 40 | pas de blocage, on signale |
| fiche `docs/` | ≤ 200 | 250 | 300 |
| une ligne de `TODOS.md`, `CODEMAP.md`, `CLAUDE.md`, `CHANGELOG.md` (hors bloc de code) | pas de cible, seule l'alerte se mesure | 800 caractères, clé `ligne` | pas de blocage, une alerte par fichier |
| tout journal (≥ 10 titres `## AAAA-MM-JJ`) | comme le CHANGELOG | | |
| règles `.claude/rules/` sans `paths` (total) | ≤ 100 | 150 | 200 |
| coût total de reprise | ≤ 450 lignes | 600 lignes, ou 60 000 caractères | 900 lignes, ou 90 000 caractères |
| index de la mémoire automatique | ≤ 100 | 150 | pas de blocage, hors dépôt |
| plan terminé | résumé de 20 lignes | plus de 300 lignes, ou une case `[ ]` ouverte | pas de blocage |

Le seuil en caractères vaut cent caractères par ligne de budget. Un budget en lignes ne voit pas un
fichier court dont chaque ligne est un tableau ou une preuve : un `CODEMAP.md` de 191 lignes peut
peser 126 000 caractères et passer sous 300 lignes. Les caractères se comptent sans les octets de
continuation UTF-8, une lettre accentuée vaut un caractère, pas deux. Ils s'ajoutent aux lignes, ils
ne les remplacent pas : le premier seuil franchi parle. Pour le coût de reprise, le message donne
aussi un ordre de grandeur en tokens, caractères divisés par quatre, qui n'entre dans aucun seuil.

Taille du projet, comptée en fichiers hors `.git`, dépendances, builds, `archives/` :

| Taille | Fichiers | Ce que la convention attend |
|---|---|---|
| petite | < 150 | un seul niveau, pas de zone |
| moyenne | 150 à 600 | des zones là où le CODEMAP racine déborde |
| grande | > 600 | des zones dès l'INIT, le CODEMAP racine est un index |

**Alerte** : à traiter à cette clôture, ou une tâche datée dans TODOS, une seule fois. Une alerte
qui revient à la clôture suivante devient un blocage. **Blocage** : la clôture n'est pas finie tant
que ce fichier dépasse ce seuil.

`ctx-audit.sh --budget` porte exactement ces chiffres, section 10. Les deux se changent ensemble,
un seuil modifié ici et pas dans le script rend l'audit faux. Les plans terminés et l'index de la
mémoire automatique se lisent en section 11, que `--budget` saute.

### Ce que le bloc règle

`seuils: <fichier>=N` fixe le seuil d'**alerte** de ce fichier à N. Le seuil de blocage suit dans
le même rapport que les valeurs par défaut du tableau, arrondi à l'entier : `CODEMAP.md=600` donne
une alerte à 600 et un blocage à 800, comme 300 et 400 par défaut. Les surfaces qui ne sont pas un
fichier ont leur clé : `reprise` (bloc de reprise), `cout-reprise`, `regles-sans-paths`,
`memoire-auto`. Le seuil en caractères d'un fichier a sa clé `car-<fichier>` (`car-CODEMAP.md=40000`
donne une alerte à 40 000 caractères et un blocage à 53 333), et celui du coût de reprise
`car-cout-reprise`. Relever le seuil en lignes d'un fichier ne relève pas son seuil en caractères.

`ajourne: <fichier>=N@AAAA-MM-JJ` gèle un dépassement à sa valeur et à sa date. Tant que le
fichier ne dépasse pas N, son alerte ou son blocage ne se dit plus, l'audit le rappelle en
information. S'il dépasse N, c'est un blocage : un dépassement gelé ne grossit plus. Dès qu'il
repasse sous son seuil d'alerte, l'audit demande de retirer l'entrée.

`taille-forcee: petite|moyenne|grande` impose la taille du projet au lieu de la mesure. L'audit
dit quand la mesure la contredit.

### Le coût total de reprise

Ce qu'une session charge avant la première question : `CLAUDE.md`, les fichiers qu'il importe par
`@` (quatre sauts), les règles `.claude/rules/` sans `paths`, le bloc de reprise de TODOS, le
`CODEMAP.md` racine et les trois dernières entrées du journal. Chaque fichier peut tenir dans son
budget et la somme déborder, c'est le cas que ce seuil attrape. `--budget` donne le détail, en
lignes puis en caractères : la somme des mêmes surfaces compte aussi 60 000 caractères d'alerte et
90 000 de blocage.

Au-delà de cinq alertes de même nature dans une section (« pas d'en-tête de statut » sur cent
fiches), le rapport en texte imprime les trois premières puis une ligne « et N autres de même
nature ». Le nombre d'alertes du bilan les compte toutes, un blocage n'est jamais regroupé, et
`--json` garde chaque entrée avec un champ `nature`.

Une règle en `globs:` ne se charge jamais par chemin, Claude Code ne lit que `paths`. Elle compte
donc dans les règles sans `paths`, et l'audit la signale.

## Le geste par fichier

### Bloc de reprise

Réécrit depuis l'état courant, jamais par édition du bloc précédent. Ce qui en sort a un
propriétaire, classe avant de retirer.

| Ce que la phrase est | Où elle va |
|---|---|
| un événement, quelque chose qui a été fait | déjà au CHANGELOG, on la retire |
| un piège, une contrainte | fiche du module, ou CODEMAP de la zone, ou, sans module ni zone, `docs/pieges/` si le projet en a un, sinon la section zones sensibles de `CODEMAP.md`, jamais les deux dans un même projet |
| une tâche | la liste de TODOS, avec son ancrage |
| une décision et son pourquoi | ADR |
| une piste écartée et pourquoi | l'ADR de la décision, ou les pièges de la fiche |
| du récit, de l'insistance, des majuscules | rien, ça ne se garde pas |

### TODOS

Supprime les cases cochées, le fait vit déjà au CHANGELOG. Sors toute section « ce que cette
session a produit » vers le CHANGELOG, TODOS ne garde que le futur. Dégraisse les tâches sans
ancrage. `ctx-audit.sh --budget` compte les cases et les sections de session, section 10.

### CHANGELOG et tout journal

```bash
bash "$SKILL/scripts/ctx-rotation.sh" --fichier CHANGELOG.md --dry-run
bash "$SKILL/scripts/ctx-rotation.sh" --fichier CHANGELOG.md
```

Déplace les entrées anciennes vers `archives/<nom>/AAAA-MM.md`, garde les 30 plus récentes.

Le plafond de 25 lignes par entrée vaut **à l'écriture**. Un journal est append-only, on ne réécrit
pas le passé, donc une vieille entrée trop longue est une information et pas une dette. L'audit ne
la signale en alerte que si elle fait partie des trois plus récentes.
Ensuite raccourcis toute entrée de plus de 25 lignes, le détail part dans la fiche du module ou
dans `docs/changes/<date>-<slug>.md`, l'entrée garde quoi, pourquoi, rollback, un pointeur.

### CODEMAP racine

Crée les zones candidates que `ctx-audit.sh --budget` liste, descends-y leurs zones sensibles et
leurs commandes, laisse un pointeur dans la table « Zones ».

```bash
bash "$SKILL/scripts/ctx-init.sh" --zone src/<dir> --with-claude
```

### CLAUDE.md

Le mode AUDIT, sinon la procédure du paragraphe suivant.

### Fiche docs/

Au-delà de 250 lignes, scinde en deux sujets distincts. Si une partie ne sert plus à décider,
sors-la vers `archives/` avec son en-tête, garde la fiche courte pour ce qui reste vrai.

Sur un fichier déjà long, l'audit signale aussi la profondeur de titres au-delà de quatre
niveaux. C'est le meilleur indice de deux sujets recousus dans une seule fiche.

### Carte de zone

Au-delà de 250 lignes, scinde la zone en deux. Le critère est le même que pour créer une zone :
un sujet qu'on a en tête en même temps, jamais deux sujets recousus dans une seule carte.

## CLAUDE.md sans le mode AUDIT

Quand le mode AUDIT est disponible, la clôture le lance sur un `CLAUDE.md` au-dessus
du seuil d'alerte, il fait une coupe avec preuve, et c'est le choix préféré quand il est là.

Sans lui, la procédure courte, en quatre étages : la racine (chargée à chaque session), une règle
liée à des chemins (`.claude/rules/<zone>.md` avec `paths:`, chez Claude Code seulement, chargée
seulement quand un fichier concerné est touché), le `CLAUDE.md` d'une zone, une fiche `docs/`.

Pour chaque ligne, dans cet ordre.

1. Est-ce un état, un récit, une date d'événement ? Rien de tout ça n'a sa place ici. L'état part
   dans TODOS, le récit dans la fiche du module, la date reste au CHANGELOG.
2. Est-ce vrai partout, quel que soit le fichier ouvert ? Elle reste à la racine.
3. Ne vaut-elle que dans une zone ? Elle descend dans `<zone>/CLAUDE.md`, ou dans
   `.claude/rules/<zone>.md` avec `paths:` si le projet préfère ce mécanisme.
4. Sinon, le test qui tranche : **retirer cette ligne ferait-il faire une erreur ?** Non, elle
   sort. Oui, elle reste, même si le fichier dépasse encore la cible.

## Découper entre sous-agents

Sur une grande codebase, ce travail se découpe par zone, un sous-agent par zone. Chacun reçoit le
chemin de la zone, sa carte actuelle et le critère de fin : la carte tient en 150 lignes et
chaque piège de la zone y est écrit.

Le principal garde ce qui ne se découpe pas : la réécriture du bloc de reprise, toute décision
d'archivage, et tout ce qui est vrai partout, qui reste à la racine et jamais seulement dans une
zone.

## Ce que le budget n'autorise pas

- Effacer un piège pour tenir le seuil. Il part chez son propriétaire, il ne disparaît pas.
- Résumer un journal au lieu de le faire tourner. `ctx-rotation.sh` déplace, il ne condense pas.
- Descendre une règle transverse dans une zone pour alléger la racine. Un agent qui travaille
  ailleurs ne la verrait plus.
- Redater une entrée ou une fiche sans l'avoir relue. Une date de fraîcheur fausse est pire
  qu'absente.
- Reporter un blocage à la clôture suivante. Un blocage se traite maintenant, une alerte peut
  attendre une fois.
- Remplacer un contenu par un `include` ou une transclusion pour raccourcir un fichier. Le coût
  est documenté ailleurs, un extrait perd son sens hors de son contexte d'origine, la maintenance
  dérive par petits correctifs locaux, et un fichier plein d'includes n'est plus lisible en un
  passage par un agent. Un import `@fichier` charge tout au démarrage, il n'allège rien.
