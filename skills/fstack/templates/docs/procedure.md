> **Statut** : ✅ à jour, vérifié le {{DATE}}
> **Type** : procédure
> **Portée** : <ce que la procédure opère>
> **Voir aussi** : `docs/modules/<...>.md`

# Procédure, <nom>

**But** : <ce qu'on obtient à la fin.>
**Quand l'exécuter** : <le déclencheur.>
**Durée et risque** : <~N minutes, réversible, ou irréversible avec <quoi>>

## Prérequis

- [ ] <accès, droit, outil installé, variable configurée>
- [ ] <état attendu du système avant de commencer>

## Étapes

<Pour chaque étape : la commande exacte, et comment savoir qu'elle a réussi. Une procédure qui
ne dit pas comment vérifier chaque étape n'est pas rejouable.>

1. **<étape>**
   ```bash
   <commande>
   ```
   ✅ Attendu : <sortie ou état observable>

2. **<étape>**
   ```bash
   <commande>
   ```
   ✅ Attendu : <sortie ou état observable>

## Vérification finale

```bash
<commande de contrôle de bout en bout>
```

## Rollback

<Comment défaire, étape par étape. Si ce n'est pas réversible, dis-le ici en toutes lettres,
avec ce qui est perdu.>

```bash
<commande>
```

## Pièges

| Symptôme | Cause | Solution |
|---|---|---|
| <message d'erreur ou comportement> | <la cause réelle> | <ce qu'il faut faire> |
