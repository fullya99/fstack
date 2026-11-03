# Les règles qui ne servent à rien

Chargé en phase 3, pour justifier un `SUPPRIMER` par une raison plutôt que par une impression.
Chaque forme ci-dessous a la même conséquence : elle coûte des tokens à chaque session et ne
change rien à ce que fait l'agent.

Une règle qui tombe dans une de ces formes n'est pas supprimée d'office. Elle est **proposée** à
la suppression, avec la raison. L'opérateur tranche.

## 1. Ce que l'agent fait déjà par défaut

> « Écris du code lisible. » · « Ajoute des commentaires utiles. » · « Gère les erreurs. »

Aucun modèle ne vise l'inverse. La ligne ne déplace rien.

**Le test** : est-ce que retirer la ligne changerait une sortie ? Si tu ne vois pas laquelle,
c'est une suppression.

**L'exception** : quand la règle dit *comment*, elle redevient utile. « Les erreurs remontent en
`Result`, jamais en exception » est une vraie contrainte.

## 2. Ce qu'un outil applique déjà

> « Indente en 2 espaces. » · « Pas de point-virgule en fin de ligne. » · « Trie les imports. »

Si Prettier, Black, `gofmt`, ESLint ou Ruff sont configurés, l'outil gagne toujours, et il gagne
après l'agent. La ligne est au mieux inutile, au pire elle contredit la config.

**La preuve à donner** : la ligne du fichier de config qui porte la règle.

```
.prettierrc:3   "semi": false
```

## 3. Ce que le projet dit déjà tout seul

> « Ce projet utilise TypeScript. » · « On est en React. » · « La base est en PostgreSQL. »

L'agent lit le manifeste et l'extension des fichiers. Redire le langage occupe de la place sans
rien apprendre.

**L'exception** : une contrainte de version qui n'est pas dans le manifeste, « on reste sur React
18, la 19 casse le rendu serveur ici », est une information réelle. Elle reste, et elle part
souvent en fiche `docs/`.

## 4. Trop vague pour être suivi

> « Sois rigoureux. » · « Fais attention aux performances. » · « Respecte les bonnes pratiques. »

Deux personnes qui lisent la ligne font deux choses différentes, donc elle ne coordonne rien.

**Le test** : est-ce que tu peux dire, en lisant un diff, si la règle a été respectée ? Non, c'est
une suppression. Une règle non vérifiable n'est pas une règle.

## 5. Le négatif sans alternative

> « N'utilise pas `any`. » · « Ne fais pas de requête dans la boucle de rendu. »

Un interdit sans remplaçant laisse l'agent trouver tout seul, et il trouve souvent pire. La règle
n'est pas fausse, elle est incomplète.

**Attention**, et c'est le piège de cette catégorie : **tu ne complètes pas la règle toi-même.**
Compléter, c'est inventer. Tu la signales à l'opérateur en phase 4, avec la question « par quoi on
remplace ». S'il ne répond pas, elle reste telle quelle.

## 6. La politesse et le méta

> « Merci de bien vouloir... » · « N'hésite pas à poser des questions. » · « Tu es un expert
> développeur senior. »

Le rôle et le ton se règlent ailleurs. Dans un fichier d'instructions de projet, ces lignes ne
portent aucune information sur le projet.

## 7. La documentation déguisée

> Vingt lignes qui décrivent l'architecture du projet, la liste des dossiers, l'historique des
> refontes.

C'est utile, mais ce n'est pas une instruction. Ça ne va pas en `SUPPRIMER`, ça va en `DOC`, ou
dans un `CODEMAP.md` si le projet en a un. Cette forme est la première cause d'un fichier racine
à 400 lignes.

## 8. La règle morte

> Une règle dont le `paths:` ne matche aucun fichier. Une consigne sur un dossier supprimé. Un
> chemin qui n'existe plus.

C'est un `FAUX` de la phase 2. Selon qu'elle explique quelque chose du code actuel ou pas, elle
part en `ARCHIVE` ou en `SUPPRIMER`.

**La preuve à donner** : la sortie du script.

```
FAUX  glob  L42  src/legacy/**/*.js  ne matche aucun fichier
```

## Le tableau des raisons, pour le rapport

Une suppression se justifie par une des raisons ci-dessous, jamais par « inutile ».

| Code | Raison courte |
|---|---|
| `defaut` | comportement déjà par défaut |
| `outil` | déjà appliqué par un linter ou un formateur |
| `evident` | déjà porté par le langage ou le manifeste |
| `vague` | non vérifiable dans un diff |
| `negatif` | interdit sans remplaçant, non complété par l'opérateur |
| `meta` | politesse, rôle, hors sujet projet |
| `mort` | référence cassée, sans valeur de trace |
| `doublon` | dit ailleurs, dans le même fichier ou dans une fiche |
