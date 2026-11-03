> **Statut** : ✅ à jour, vérifié le {{DATE}}
> **Type** : feature
> **Portée** : `<chemins impliqués>`
> **Voir aussi** : `docs/modules/<...>.md`

# Feature, <nom>

**Ce que ça fait, et pour qui** : <une ou deux phrases, du point de vue de l'utilisateur, pas
du code.>

**État** : <en production, ou derrière un flag `<nom>`, ou partiel avec <ce qui manque>>

## Parcours

<Le chemin de bout en bout, avec les fichiers traversés. C'est la section qui fait gagner le
plus de temps à un lecteur à froid.>

1. <déclencheur : action utilisateur, appel, événement> → `<fichier>`
2. <traitement> → `<fichier>`
3. <résultat observable> → `<fichier>`

## Fichiers impliqués

| Fichier | Rôle dans la feature |
|---|---|
| `<chemin>` | <une ligne> |

## Configuration

| Réglage | Où | Valeur par défaut | Effet |
|---|---|---|---|
| `<nom>` | `<var d'env ou fichier>` | `<valeur>` | <ce que ça change> |

## Cas limites et erreurs

| Situation | Comportement attendu |
|---|---|
| <entrée invalide, service indisponible, concurrence, quota> | <ce qui se passe> |

## Limites connues

- <ce que la feature ne fait pas, ou pas encore, et pourquoi>

## Comment vérifier que ça marche

```bash
<commande, requête ou scénario manuel rejouable>
```

Résultat attendu : <ce qu'on doit observer>
