# Anatomie d'un plan

## 1. Ossature commune

Dans cet ordre. Le gabarit à remplir est dans `templates/plan.md`.

1. **Objectif et cas de validation.** Le résultat en une phrase, et la chose observable qui dira
   que c'est fini. Pas « le système est amélioré », plutôt « la commande `X` répond en moins de
   deux secondes sur le jeu de données `Y` ».
2. **Décisions verrouillées.** Numérotées, chacune avec sa justification en une ligne, marquées
   comme non discutables pour la suite. C'est ce que la phase 3 a tranché avec l'opérateur.
3. **Ce qu'on ne touche pas.** Fichiers, modules et comportements hors d'atteinte, nommés
   explicitement. C'est la clôture qui empêche une session d'exécution de partir en vrille et
   d'élargir le chantier de son propre chef.
4. **Recherche.** Ce qui a façonné la conception, chaque point avec son lien et sa date. Si la
   tâche n'avait pas de surface externe, la section le dit en une ligne et s'arrête là.
5. **État actuel.** Chemins et symboles réels dont le travail part. Aucun placeholder abstrait du
   genre « le module de gestion des utilisateurs », le vrai chemin ou rien.
6. **Invariants.** Ce qui doit rester vrai à chaque étape du travail : tests qui passent,
   compatibilité ascendante, aucun secret sur disque, ce que le projet impose de son côté.
7. **Portes préalables.** Trois questions tranchées par écrit avant d'écrire la conception, la
   réponse va dans le plan, pas seulement dans la tête de qui l'a écrit.
   - Simplicité : une version plus petite règle-t-elle le vrai besoin ?
   - Anti-abstraction : ajoute-t-on une couche que rien n'exige aujourd'hui ?
   - Intégration d'abord : le bout en bout marche-t-il avant qu'on peaufine une partie ?
   Une porte qu'on décide de forcer se justifie dans le registre des écarts, jamais en silence.
8. **Registre des écarts.** Ce qu'on s'est autorisé contre une porte, et pourquoi. Une porte
   forcée sans entrée ici, c'est un plan qui a déjà commencé à dériver avant même la première
   tâche.
9. **Conception.** Les changements, fichier par fichier.
10. **Tâches.** Le format est fixé plus bas, il s'impose tel quel.
11. **Découpage pour l'équipe.** Quels lots partent en parallèle, lesquels sont sériels, et
    pourquoi, avec un rôle par lot, pris dans `references/DELEGATION.md`. Deux lots qui touchent les mêmes
    fichiers ne partent jamais ensemble.
12. **Contre-revue.** Les constats `F-01`, `F-02` et suivants, classés Bloquant, Majeur, Modéré ou Validé, chacun
    avec sa décision écrite, intégré (section citée) ou rejeté (raison). Un constat sans décision
    interdit de rendre le plan.
13. **Hors périmètre et différé.**
14. **Risques et pièges connus.**
15. **Reprise.** De quoi redémarrer dans une session qui ne sait rien : où on en est, la
    prochaine tâche non cochée, ce qui est déjà validé et ne se refait pas, la commande qui donne
    l'état du terrain (tests, lint, git status du projet). Elle se met à jour au fil de
    l'exécution, elle n'est pas figée à l'écriture du plan.

## 2. Format d'une tâche

Repris tel quel, sans variation d'un plan à l'autre.

```
### Tâche N, <nom court>

**Fichiers**
- créer : <chemins exacts>
- modifier : <chemins exacts>
- tester : <chemins exacts>

**Interfaces**
- consomme : <signatures exactes>
- produit : <signatures exactes>

**Étapes**
- [ ] <une action vérifiable, deux à cinq minutes>
- [ ] <...>

**Vérification** : <la commande ou l'observation qui dit que la tâche est finie>
```

Les interfaces se relisent dans les deux sens avant de rendre le plan : tout ce qu'une tâche
consomme est produit par une tâche antérieure ou existe déjà (chemin vérifié), et tout ce qu'une
tâche produit est consommé par une suite ou par le cas de validation. Une production que rien ne
consomme est une tâche orpheline, elle atteint son critère de fin sans servir à rien.

## 3. Niveau de preuve

Toute affirmation sur le comportement d'un outil, d'une API ou d'un service dit son niveau, dans
la phrase même : `prouvé le AAAA-MM-JJ par <commande>`, `doc de première main <lien>`, ou
`déduit, à prouver avant la tâche N`. Dans un tableau, le niveau va dans une colonne de chaque
ligne, jamais dans un « vérifié » global en tête du tableau : un chiffre non mesuré placé sous un
chapeau « vérifié » finit recopié ailleurs comme un fait.

## 4. Ce qui est interdit dans un plan

« TBD », « TODO », « à voir », « ajouter la validation appropriée », un chemin inventé, une
fonction dont on n'a pas vérifié l'existence, une étape sans critère de vérification. Chacun de
ces cas rend le plan inexécutable par quelqu'un d'autre, et c'est justement le but du plan : que
la session d'exécution n'ait rien à deviner.

## 5. Sections que le type ajoute

Selon le type retenu en phase 0, `TYPES-DE-PLAN.md` liste des sections en plus de l'ossature
commune. Ce fichier ne les redit pas, il renvoie à la table.

## 6. Emplacement et nommage

`plans/<slug>.md` à la racine du projet, slug en minuscules et tirets, descriptif. Si le projet a
déjà un endroit où il range ses plans, on l'utilise à sa place.

## 7. Quand ne pas écrire de plan

La tâche tient en deux étapes et trois fichiers, ou le projet a déjà un suivi qui ferait
l'affaire (`TODOS.md`, une issue, un board). Le dire à l'opérateur et proposer l'alternative
plutôt que de produire un plan pour une tâche qui n'en a pas besoin.
