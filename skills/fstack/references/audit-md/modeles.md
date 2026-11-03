# Gabarits

Chargé en phase 5. Deux gabarits, celui du fichier racine et celui d'une fiche. Ce sont des
formes, pas des textes à recopier : le contenu vient toujours du projet audité.

---

## Le fichier racine

Cible 100 lignes, alerte 150, blocage 200. Quatre sections, dans cet ordre et rien d'autre.

````markdown
# <nom du projet>

<Deux phrases. Ce que fait le projet, et la seule chose qu'un nouvel arrivant doit savoir
avant de toucher au code.>

## Commandes

```bash
<installer>
<lancer en dev>
<tester>
<linter>
```

## Contraintes

- **<Un interdit sans exception.>** <La raison, en une ligne, quand elle n'est pas évidente.>
- **<Un autre.>**

## Où chercher le reste

| Quand | Où |
|---|---|
| <la situation qui fait ouvrir> | `docs/<sujet>.md` |
| <la situation qui fait ouvrir> | `docs/<sujet>.md` |
````

**Les commandes sont copiées du manifeste réel**, pas retapées de mémoire. Si `npm run dev`
n'existe pas dans `package.json`, il n'entre pas ici.

**La section contraintes ne prend que ce qui n'a aucune exception.** Une règle avec un « sauf
dans... » part en fiche, et son exception avec elle.

**La table de renvoi est la partie qui fait tenir les 50 lignes.** Sans elle, tout remonte. Sa
colonne de gauche dit la situation, pas le domaine : c'est elle qui décide si la fiche s'ouvre. Une
table qui liste des sujets est une liste de fichiers, et elle sera ignorée.

Les règles parties en `.claude/rules/` n'ont pas besoin d'une ligne ici, elles se chargent toutes
seules. Une ligne reste utile quand le dépôt est lu par un autre agent que Claude Code, qui ne
connaît pas cet étage.

Si le fichier dépasse 100 lignes après restructuration, c'est qu'un bloc classé `RACINE` aurait dû
sortir. Reprends la phase 3 sur les blocs les plus longs, pas sur tous.

---

## Une règle liée à des chemins

C'est la meilleure sortie quand la contrainte doit tenir sur un dossier précis, parce qu'elle se
charge toute seule au bon moment. Claude Code uniquement.

````markdown
---
paths:
  - "<glob qui matche au moins un fichier>"
---

# <Sujet>

- **<Règle.>** <Ce qu'on fait.>
- **<Règle.>**
````

Le glob se vérifie avant d'écrire le fichier. Un `paths:` qui ne matche rien donne une règle morte,
et rien ne le signale. Un `[` non échappé dans un glob le rend invalide, il matche zéro fichier.

## Une fiche `docs/`

Un sujet par fiche. Au-delà de 150 lignes, coupe en deux. En dessous de 15, ne la crée pas.

````markdown
# <Sujet>

> S'applique quand <la condition de lecture, en une ligne : on touche à tel dossier,
> on ajoute telle chose, on débogue tel symptôme>.

<Deux ou trois lignes de contexte. Ce que le lecteur doit avoir en tête avant les règles.>

## Les règles

- **<Règle.>** <Ce qu'on fait, pas ce qu'on évite.>
- **<Règle.>**

## Les pièges

<Ce qui a déjà coûté du temps à quelqu'un. Un symptôme, une cause, une réparation.>

## Voir aussi

- `<chemin/vers/un/fichier>`
- `docs/<autre-sujet>.md`
````

**La première ligne dit quand lire la fiche.** C'est ce qui permet à l'agent de décider de
l'ouvrir ou pas, et c'est la seule partie que quelqu'un lira à coup sûr.

**Les pièges valent plus que les règles.** Une règle se devine souvent, un piège jamais.

---

## L'en-tête d'archive

Tout ce qui part dans `archives/` porte cet en-tête. Sans lui, `archives/` devient un cimetière
qu'on relit par erreur comme une source.

```markdown
> **Archivé le <AAAA-MM-JJ>.** Venait de `<fichier d'origine>`.
> Raison : <ce qui a rendu ça faux, en une ligne>.
> Ne pas lire comme une source de vérité.
```

Le nom du fichier d'archive reprend le sujet et la date, `archives/<AAAA-MM-JJ>-<sujet>.md`. Si le
projet a déjà sa convention de nommage dans `archives/`, elle gagne.

---

## Le rapport de la phase 6

Quatre morceaux, dans cet ordre. C'est ce que l'opérateur lit avant de dire oui.

````markdown
## 1. Vérifications

| Statut | Ligne | Affirmation | Preuve |
|---|---|---|---|

## 2. Fichier racine

<N> lignes avant, <N> après, soit <N> % en moins. Diff :

```diff
```

## 3. Ce qui sort

| Destination | Étage | Lignes | Vient de |
|---|---|---|---|

## 4. Suppressions

| Ligne | Contenu | Raison | Preuve |
|---|---|---|---|
````

Les contradictions de la phase 4 viennent avant tout ça, sous forme de questions. Le rapport ne
se présente pas tant qu'elles ne sont pas tranchées, sauf si l'opérateur demande à voir le reste
d'abord.
