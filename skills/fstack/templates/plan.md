# <titre court du plan>

<!-- Slug de fichier : plans/<slug>.md, minuscules et tirets. -->

## Objectif et cas de validation

<!-- Le résultat en une phrase, et la chose observable qui dira que c'est fini. -->

<phrase d'objectif>

**Validation** : <observation ou commande qui prouve que c'est fait>

## Décisions verrouillées

<!-- Numérotées, une justification en une ligne chacune. Ne pas rouvrir en cours d'exécution. -->

1. <décision> : <justification>
2. <décision> : <justification>

## Ce qu'on ne touche pas

<!-- Fichiers, modules, comportements hors d'atteinte. Explicite, pas de sous-entendu. -->

- <chemin ou comportement>

## Recherche

<!-- Ce qui a façonné la conception, un lien et une date par point. -->
<!-- Si la tâche n'avait pas de surface externe, écrire la phrase telle quelle et rien d'autre. -->

- <affirmation> : <lien>, <date>

Ou : cette tâche n'a pas de surface externe, aucune recherche menée.

## État actuel

<!-- Chemins et symboles réels dont le travail part. Aucun placeholder abstrait. -->

- <chemin réel> : <ce qui s'y trouve aujourd'hui>

## Invariants

<!-- Ce qui doit rester vrai à chaque étape : tests qui passent, pas de secret sur disque,
     compatibilité ascendante, contraintes imposées par le projet. -->

- <invariant>

## Portes préalables

<!-- Trois questions tranchées par écrit avant la conception. Une porte forcée va au registre
     des écarts, jamais en silence. -->

- **Simplicité** : une version plus petite règle-t-elle le vrai besoin ? <réponse>
- **Anti-abstraction** : ajoute-t-on une couche que rien n'exige aujourd'hui ? <réponse>
- **Intégration d'abord** : le bout en bout marche-t-il avant qu'on peaufine une partie ? <réponse>

## Registre des écarts

<!-- Ce qu'on s'est autorisé contre une porte préalable, et pourquoi. Vide si rien n'a été forcé. -->

- <écart> : <raison>

## Conception

<!-- Les changements, fichier par fichier. -->

### <fichier ou zone>

<ce qui change et pourquoi>

## Tâches

<!-- Une entrée par tâche, ce format tel quel. -->

### Tâche 1, <nom court>

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

## Découpage pour l'équipe

<!-- Quels lots partent en parallèle. Lesquels sont sériels, et pourquoi. Deux lots qui touchent
     les mêmes fichiers ne partent jamais ensemble. -->

<!-- Un rôle par lot, pris dans `references/DELEGATION.md` : explorateur, controleur, executant, developpeur,
     chercheur, expert ou relecteur. Le plus bas qui tient le critère de fin du lot. -->

- Lot A (<tâches>), rôle <rôle> : parallèle avec <lot ou rien>
- Lot B (<tâches>), rôle <rôle> : après <lot>, parce que <raison>

## Contre-revue

<!-- Un relecteur en contexte neuf challenge les hypothèses du plan. Une décision écrite par constat,
     sans quoi le plan ne se rend pas. -->

| Id | Niveau | Constat et source | Décision |
|---|---|---|---|
| F-01 | Bloquant, Majeur ou Modéré | <ce qui est faux, lien> | intégré (<section>) ou rejeté (<raison>) |

Validé : <constats confirmés par une source primaire, en une ligne>

## Hors périmètre et différé

<!-- Ce qu'on a choisi de ne pas faire ici, et pourquoi ça peut attendre. -->

- <point>

## Risques et pièges connus

<!-- Ce qui a des chances de mal tourner, tiré de la recherche ou de l'exploration. -->

- <risque> : <comment le repérer ou l'éviter>

## Reprise

<!-- De quoi redémarrer dans une session qui ne sait rien. Se met à jour au fil de l'exécution,
     jamais figée à l'écriture du plan. -->

- État actuel : <phrase>
- Prochaine tâche : <numéro et nom de la tâche>
- Déjà validé, ne pas refaire : <liste>
- Commande d'état du terrain : <commande tests, lint, git status>
