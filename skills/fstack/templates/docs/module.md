> **Statut** : ✅ à jour, vérifié le {{DATE}}
> **Type** : module
> **Portée** : `<chemin/**>`, `<autre/fichier>`
> **Voir aussi** : `docs/features/<...>.md`, `docs/decisions/ADR-00NN-<...>.md`

# Module, <nom>

**Rôle** : <ce que fait cette brique, en une ou deux phrases. L'essentiel d'abord, un lecteur
qui s'arrête ici doit déjà avoir compris.>

## Où ça vit

| Fichier | Rôle |
|---|---|
| `<chemin>` | <une ligne> |

## Interface

<Ce que le reste du projet consomme : fonctions, classes, endpoints, événements, CLI. Les
signatures exactes vivent dans le code, ici tu dis à quoi ça sert et comment on s'en sert.>

| Élément | Signature ou forme | Usage |
|---|---|---|
| `<nom>` | `<forme>` | <quand l'appeler> |

## Fonctionnement

<Comment ça marche à l'intérieur, uniquement pour ce qui ne se lit pas dans le code : ordre des
étapes, état conservé, cas particuliers structurants.>

## Invariants, ce qui casse si on y touche

- <règle non évidente que le code suppose vraie>
- <dépendance d'ordre, contrat implicite, effet de bord>

## Pièges

- <symptôme observé> → <cause réelle> → <ce qu'il faut faire>

## Dépendances

- **Utilise** : `<module ou service>`, <pour quoi faire>
- **Utilisé par** : `<module>`, <pour quoi faire>

## Tests

| Quoi | Où | Commande |
|---|---|---|
| <cas couverts> | `<chemin>` | `<cmd>` |

**Non couvert** : <ce qu'aucun test ne protège. C'est souvent l'information la plus utile de
la fiche.>
