# Les huit types de plan

Le type se choisit en phase 0, sans lire de code. Il décide de l'angle de recherche et des
sections que le plan ajoute à son ossature commune.

| Type | Recherche prioritaire | Sections en plus | Piège typique |
|---|---|---|---|
| Fonctionnalité | l'état de l'art de la pratique, l'API des libs touchées | contrat d'interface, cas limites | on décrit la solution avant d'avoir écrit le comportement attendu |
| Correctif | le comportement documenté de la version en place, les issues connues | reproduction, cause racine, non-régression | on corrige le symptôme, la cause reste |
| Migration | les notes de version entre la version de départ et la cible, les ruptures | inventaire des points d'appel, ordre de bascule, retour arrière | on découvre un point d'appel à mi-parcours |
| Refonte | rien, sauf si l'abstraction visée vient d'ailleurs | parité de comportement avant et après, périmètre gelé | le périmètre grossit en cours de route |
| Infrastructure et déploiement | la doc du fournisseur, les coûts, les quotas | ce qui est détruit, ce qui est réversible, l'ordre des opérations | une étape irréversible passe sans confirmation |
| Documentation et contenu | la source de vérité de ce qu'on documente | qui lit, ce qu'il sait déjà, ce qu'il doit pouvoir faire après | on documente l'intention, pas ce qui existe |
| Investigation | large, c'est le coeur du travail | la question à trancher, ce qui compterait comme réponse, le budget | l'investigation n'a pas de critère d'arrêt |
| Hors code | le domaine propre au sujet, jamais un axe technique | qui décide, qui exécute, quand c'est fini | on écrit un plan technique pour un sujet qui ne l'est pas |

## Fonctionnalité

La phase 3 pose une question de plus que les autres types : le cas limite qu'on choisit de couvrir
ou d'exclure. La phase 4 écrit le contrat d'interface avant la conception, pas après. Un plan qui
saute cette section décrit du code sans dire ce qu'il doit produire.

## Correctif

La phase 2 commence par reproduire le bug avant d'explorer, sinon l'exploration part dans le vide.
La cause racine se nomme par fichier et ligne, pas par hypothèse. La section non-régression liste
le test qui aurait dû échouer avant le correctif.

## Migration

La phase 1 cherche d'abord les notes de version entre la version de départ et la cible, avant tout
autre axe. La phase 2 inventorie chaque point d'appel réel, un par un, avant d'écrire l'ordre de
bascule. Un plan de migration sans registre de retour arrière n'en est pas un.

## Refonte

Pas de recherche externe sauf si l'abstraction visée vient d'un autre projet ou d'un pattern
documenté ailleurs. La phase 3 verrouille le périmètre en clair et la phase 4 fige la parité de
comportement avant et après comme critère de fin.

## Infrastructure et déploiement

La phase 1 cherche la doc du fournisseur avant tout, plus les coûts et les quotas réels. La phase 4
ordonne les opérations en distinguant ce qui est réversible de ce qui ne l'est pas, et toute étape
irréversible demande une confirmation explicite avant de partir.

## Documentation et contenu

La phase 0 identifie qui va lire et ce qu'il sait déjà, avant de chercher quoi que ce soit. La
phase 2 explore le code ou le produit réel, pas les intentions du projet. Le plan documente ce qui
existe, pas ce qu'on voulait qu'il fasse.

## Investigation

Pas de plan d'implémentation, un plan de recherche. La phase 3 pose la question précise à trancher
et le budget de temps alloué, sinon l'investigation n'a pas de fin. « Ce qui compterait comme
réponse » se décide avant de chercher, pas après.

## Hors code

Les phases 1 et 2 changent de nature : la recherche porte sur le domaine du sujet, l'exploration
porte sur les documents et décisions existants du projet, pas sur un dépôt git. Le plan remplace
la conception technique par qui décide, qui exécute, à quel moment c'est fini.

## Un plan à cheval sur deux types

Une tâche peut relever de deux types à la fois, une migration qui touche l'infra par exemple. Dans
ce cas on prend le type le plus contraignant pour l'angle de recherche, et on ajoute les sections
en plus des deux types concernés.
