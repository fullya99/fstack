# CONVENTION : spécification des 3 piliers

> Référence détaillée. Le résumé opérationnel est dans `SKILL.md`.
> Tout ce que tu écris ici suit la règle du skill `style-redaction`.

## Le principe : une question par fichier

Si la doc pourrit, c'est rarement parce qu'on écrit trop peu. C'est parce qu'on demande à un
seul fichier de faire plusieurs métiers. Il devient un mur d'exceptions que plus personne ne
lit, donc que plus personne ne met à jour.

La convention répartit la connaissance selon la question à laquelle elle répond, et selon sa
durée de vie.

| Surface | Question | Durée de vie | Chargement |
|---|---|---|---|
| `CLAUDE.md` ou `AGENTS.md` | Comment on travaille ici ? | Très stable | Toujours, automatique |
| `CODEMAP.md` | Où ça se trouve ? | Stable, évolue avec la structure | À la reprise |
| `TODOS.md` | Quoi maintenant ? | Volatile | À la reprise |
| `CHANGELOG.md` | Qu'est-ce qui a changé ? | Append-only | 2 ou 3 entrées à la reprise |
| `docs/` | Comment ça marche en détail ? | Longue, mais datée | À la demande, ciblé |
| `archives/` | Qu'est-ce qui était vrai avant ? | Figée | Jamais, sauf archéologie |

Corollaire : ne mets jamais la même information dans deux surfaces. Une info dupliquée est une
info qui va diverger. Tu mets un pointeur, pas une copie.

Il n'y a **pas de fichier de mémoire** dans cette convention, et ce n'est pas un oubli. Un
fichier dont la définition est « ce que le code ne dit pas » se remplit de tout, et recopie ce
que les autres surfaces portent déjà. Chaque savoir a donc un propriétaire unique.

| Ce que tu as appris | Où ça va |
|---|---|
| Décision et son pourquoi | `docs/decisions/ADR-NNNN-*.md` |
| Piège d'un module | La fiche du module, ou la carte de sa zone `<zone>/CODEMAP.md` |
| Une piste écartée et pourquoi | L'ADR de la décision, ou les pièges de la fiche |
| Piège sans module identifiable et sans zone | `docs/pieges/` si le projet en a un, sinon la section zones sensibles de `CODEMAP.md`, jamais les deux dans un même projet |
| Préférence durable de l'utilisateur | `CLAUDE.md` |
| Contrainte d'environnement, accès, outil disponible | `CODEMAP.md`, section dépendances |
| Fait externe daté et périssable | `docs/veille/`, ou une entrée de `CHANGELOG.md` |

Le test à l'écriture tient en une question : **qui est propriétaire de cette phrase ?** Si tu ne
sais pas répondre, c'est presque toujours qu'elle n'a pas besoin d'être écrite.

Attention à un homonyme. Claude Code tient sa propre mémoire automatique dans un fichier nommé
`MEMORY.md`, sous `~/.claude/projects/<projet>/memory/`. Il est local à la machine, il ne survit
ni à un clone ni à un changement de poste, et il ne fait pas partie de cette convention. Ne le
commite pas. La clôture le draine vers les propriétaires (voir `MEMOIRE-AUTO.md`), et rien ne
s'écrit du dépôt vers lui. Le dépôt fait autorité.

---

## Emplacement et adaptation

Le bloc en tête de `CODEMAP.md` déclare les chemins réels du projet. Ça rend la convention
auto-descriptive. Un projet qui utilise `documentation/` au lieu de `docs/` le déclare, et
tout le reste suit.

```html
<!-- contexte:convention
version: 5
profil: app
piliers: CODEMAP.md, TODOS.md, CHANGELOG.md
docs: docs/
archives: archives/
langue: fr
-->
```

Sans ce bloc, on suppose les chemins par défaut ci-dessus. La ligne `version` est la seule
obligatoire, elle fait refuser un bloc trop récent aux scripts trop anciens. La taille du projet
ne s'écrit plus, l'audit la calcule en nombre de fichiers hors dépendances : petite sous 150,
moyenne jusqu'à 600, grande au-delà. Les autres clés (seuils, journal, exceptions) et leurs
défauts sont dans `references/CONFIG-PROJET.md`.

**Ce que la stack parcourt.** La gestion de contexte ne s'arrête jamais à ce que git suit : un
fichier gitignoré (notes locales, `context-input/`, livrables, `CLAUDE.local.md`) reste du
contexte, la liste des fichiers ne vient donc jamais de `git ls-files` et rien n'est exclu parce
que le `.gitignore` l'exclut. Seul le généré lourd s'élague, reconnu à sa nature : une liste fixe
de dossiers, les dossiers qui portent un `CACHEDIR.TAG`, les dossiers d'un moteur de jeu quand son
marqueur existe, à la racine ou jusqu'à trois niveaux plus bas. Tout élagage est nommé par l'audit, jamais silencieux. Un fichier
gitignoré compte donc, mais il ne voyage ni vers un collègue ni vers une autre machine : l'audit
l'annonce en information. `ignorer:` écarte ce que git suit sans qu'il fasse partie du projet.

Sur une codebase moyenne ou grande, la carte se découpe par zones. Une zone est un répertoire qui
porte la sienne, `<zone>/CODEMAP.md`. L'état et le journal restent uniques à la racine. Le détail
est dans `references/ZONES.md`.

**Multi-niveaux** : chaque unité autonome (racine, package d'un monorepo, sous-projet) a son
propre kit. Le parent ne recopie pas le contenu des enfants, il les liste et pointe vers eux.
Une session qui touche plusieurs niveaux les met tous à jour.

---

## CODEMAP.md, la carte

**Rôle** : trouver le bon fichier en une lecture, et comprendre ce qui casse quand on le
modifie. Ce fichier n'est ni une doc d'API ni un tutoriel.

**Ce qu'on y met**

1. Le bloc `contexte:convention`, profil et chemins.
2. **Une phrase** qui dit ce que fait le projet. Un lecteur qui ne connaît rien doit pouvoir
   décider en dix secondes s'il est au bon endroit.
3. **Arborescence commentée.** Les répertoires qui comptent, une ligne de rôle chacun. Pas de
   sortie brute de `tree`. Tu cites ce qui porte du sens, tu omets le bruit (dépendances,
   builds, caches).
4. **Modules.** Un tableau avec le nom, le chemin, le rôle en une ligne et la fiche `docs/`
   si elle existe.
5. **Points d'entrée.** Par où le code démarre vraiment : main, serveur, CLI, handler, cron,
   worker. C'est ce qu'on cherche en premier et qu'on trouve le moins vite.
6. **Flux principal.** Le chemin nominal d'une requête ou d'un traitement, en trois à six
   étapes, avec les fichiers traversés. Rien ne remplace ça pour un lecteur à froid.
7. **Dépendances externes.** Services, API, bases, files, comptes. Tout ce dont le projet a
   besoin pour tourner. **Jamais de secret** : tu dis où est la clé, pas ce qu'elle vaut.
8. **Commandes.** Install, run, test, lint, build, deploy. Les vraies, celles que tu as testées.
9. **Zones sensibles.** Code généré à ne pas éditer, fichiers à ne toucher qu'avec précaution,
   conventions non évidentes. Racine : seulement ce qui n'a ni zone ni fiche. Ce qui concerne une
   zone descend dans `<zone>/CODEMAP.md`.
10. **Zones.** Une table qui liste les zones du projet et pointe vers leur carte, sans recopier.
11. La date de dernière mise à jour.

**Ce qui n'y va pas** : l'historique (CHANGELOG), les tâches (TODOS), le pourquoi des décisions
(`docs/decisions/`), les détails d'implémentation (`docs/modules/`).

**Longueur visée** : cible 250 lignes, alerte à 300, blocage à 400. Ce qui déborde descend dans
une carte de zone, voir `references/ZONES.md`.

---

## TODOS.md, l'état de reprise

**Rôle** : c'est le fichier qui rend le `/clear` sans danger. Il porte à la fois ce qu'il reste
à faire, et où on en était exactement.

**Structure imposée**

```markdown
# TODOS, <projet>

## 🔄 État à la reprise, AAAA-MM-JJ
**Où on en est** : <2 à 4 lignes factuelles, ce qui marche, ce qui est en place>
**En cours** : <la tâche entamée et pas finie, avec les fichiers concernés, ou « rien »>
**Prochaine étape** : <la toute prochaine action concrète, pas un objectif vague>
**À savoir avant de toucher** : <pièges, état instable, travail à moitié appliqué>

## 🔴 Bloqué
- [ ] <tâche>, bloquée par <quoi>, à débloquer en <comment>

## 🎯 Prochaines étapes
- [ ] <tâche actionnable, verbe à l'infinitif, avec le fichier ou la zone>

## 🧹 Dette et améliorations
- [ ] <ce qu'on sait imparfait, avec l'impact, pas juste « refactorer »>

## 💡 Idées non engagées
- <ce qu'on ne fera peut-être jamais, à purger sans état d'âme>
```

**Les règles**

Le bloc « État à la reprise » tient en 40 lignes, et se **réécrit depuis l'état courant** à
chaque clôture, jamais en éditant le bloc précédent. C'est un état, pas un journal.

Une tâche cochée n'est pas archivée, elle est **supprimée**. Sa trace est au CHANGELOG. TODOS
ne garde que le futur.

Toute tâche mentionne un point d'ancrage : un fichier, un module, une commande. « Améliorer les
perfs » ne sert à rien après un `/clear`. « Réduire les N+1 dans `repo/orders.py:list_orders` »
se reprend tout de suite.

Rien d'entamé ne doit rester hors de ce fichier avant un `/clear`.

**Ce qui sort du bloc a un propriétaire**

| Ce que la phrase est | Où elle va |
|---|---|
| un événement, quelque chose qui a été fait | déjà au CHANGELOG, on la retire |
| un piège, une contrainte | fiche du module, ou CODEMAP de la zone, ou zones sensibles racine si aucune zone |
| une tâche | la liste de TODOS, avec son ancrage |
| une décision et son pourquoi | ADR |
| une piste écartée et pourquoi | l'ADR de la décision, ou les pièges de la fiche |
| du récit, de l'insistance, des majuscules | rien, ça ne se garde pas |

Trois interdits dans TODOS : pas de section « ce que cette session a produit », c'est du
CHANGELOG. Pas de case cochée conservée, le fait vit au CHANGELOG. Pas de section « décidé »,
c'est un ADR ou rien. Une affirmation non vérifiée porte « à vérifier », la session suivante
vérifie avant d'agir dessus.

**Fichier entier** : cible 150 lignes, blocage à 300.

---

## Les savoirs durables, et où ils atterrissent

Ce sont les faits qu'aucune lecture du dépôt ne permet de retrouver. Le tableau plus haut donne
la destination de chacun, voici le détail qui n'y tient pas.

**ADR**, `docs/decisions/`, gabarit `templates/docs/ADR.md`. Contexte, options envisagées,
décision, conséquences, ce qui devrait la faire reconsidérer. Un ADR accepté **ne se réécrit
jamais** : la décision change, un nouvel ADR le supersède et l'ancien pointe vers le nouveau.

**Piège**, la fiche `docs/` du module, la carte de sa zone, ou `CODEMAP.md` zones sensibles s'il
n'a ni l'un ni l'autre. Écrit comme un symptôme suivi de sa cause, pas comme une consigne.
« L'API renvoie 200 avec l'erreur dans le corps » se retient, « attention aux erreurs » ne sert
à rien.

**Préférence de l'utilisateur**, `CLAUDE.md`, qui se charge tout seul. Style demandé,
conventions imposées, ce qu'il ne veut pas qu'on fasse. Reste court, seulement du permanent.

**Contrainte d'environnement ou d'accès**, `CODEMAP.md` section dépendances. Quel service, quel
compte, quelle région, où vit la clé. **Jamais la valeur d'un secret.**

**Fait externe daté**, `docs/veille/` avec sa date, ou une entrée de `CHANGELOG.md` si c'est ce
qui explique un changement. Périssable par nature, il se relit ou s'archive.

**Règles communes.** Dates absolues, « la semaine dernière » devient faux dès le lendemain. Un
fait porte son pourquoi, pas seulement son quoi. Une règle durable devenue fausse est
**supprimée tout de suite**, pas archivée, sa disparition va au CHANGELOG si elle mérite une
trace, les ADR seuls se supersèdent. En cas d'hésitation, choisis le propriétaire que relira
quelqu'un qui travaille sur le sujet.

---

## CHANGELOG.md, le journal

**Rôle** : répondre à « qu'est-ce qui a changé, quand, pourquoi et comment on revient en
arrière ». C'est la seule surface append-only de la convention.

**Format**

```markdown
## 2026-08-13, titre court et factuel

**Quoi** : ce qui a changé, concrètement. Fichiers, comportements, ressources.
**Pourquoi** : le besoin ou le problème derrière.
**Rollback** : comment défaire. Commit à révoquer, config à restaurer, migration inverse.
**Voir aussi** : `docs/...`, ADR, ticket.
```

**Les règles**

Plus récent en haut. Une entrée par session utile, pas une par commit.

Le rollback n'est pas optionnel dès qu'un changement touche une donnée, un déploiement, une
dépendance ou une configuration. C'est ce qui sauve la session suivante.

Tu ne réécris jamais le passé. Une entrée erronée se corrige par une nouvelle entrée qui la
mentionne, pas par une édition silencieuse.

Une entrée volumineuse reste courte ici et pointe vers `docs/`, ou vers `changes/<date>-<slug>.md`
si le projet a ce répertoire. Une entrée tient en 25 lignes, le détail va dans une fiche.

Au-delà de 30 entrées le journal tourne avec `$SKILL/scripts/ctx-rotation.sh` vers
`archives/changelog/AAAA-MM.md`, et le fichier garde en tête la ligne qui le dit. Une entrée
froide n'est pas fausse, c'est pourquoi elle va dans le seul endroit qu'on ne lit pas en reprise.

Si le projet publie des versions, tu peux adopter la structure Keep a Changelog
(`## [1.4.0] 2026-08-13`, avec des sections Ajouté, Modifié, Corrigé, Retiré). La règle
quoi, pourquoi, rollback reste applicable dans chaque section.

---

## Ce qui vit dans CLAUDE.md, et pas ici

`CLAUDE.md` est chargé automatiquement à chaque session. C'est la surface la plus coûteuse en
contexte. Tu y mets uniquement ce qui doit être vrai à chaque instant : commandes à utiliser,
interdits durs, préférences durables de l'utilisateur, style, et le pointeur vers la convention
de contexte.

Le reste vit ailleurs et se charge à la demande. La carte dans CODEMAP, l'état dans TODOS,
l'historique dans CHANGELOG, les décisions dans `docs/decisions/`, le détail dans `docs/`.

C'est `CLAUDE.md` qui absorbe le plus facilement ce qui n'a pas de propriétaire évident, et
c'est le risque à surveiller. Une règle qui n'est pas vraie à chaque instant n'a rien à y faire.
Relis-le à chaque clôture avec cette question en tête, et coupe. Le bloc à coller est dans
`templates/CLAUDE-snippet.md`.

`CLAUDE.md` ne porte ni état, ni récit, ni date d'événement. Cible 100 lignes, blocage à 200
lignes ou 40 000 caractères. Une règle qui ne vaut que dans une zone descend dans
`<zone>/CLAUDE.md`, ou dans `.claude/rules/<zone>.md` avec `paths:` chez Claude Code.
