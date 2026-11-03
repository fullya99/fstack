<!-- Carte de zone. Se lit à la demande, quand on travaille dans {{ZONE}}.
     Pas de TODOS ni de CHANGELOG ici : l'état et le journal restent uniques, à la racine.
     Cible 150 lignes, au-delà de 250 la zone se scinde. -->

# Carte de zone, {{ZONE}}

> Ce que cette zone fait, et ce qui casse quand on y touche. Fait partie de {{PROJECT_NAME}},
> dont la carte générale est `CODEMAP.md` à la racine.
> Dernière mise à jour : {{DATE}}

**En une phrase** : <ce que fait cette zone, et qui la consomme>.

---

## Arborescence

```
{{ZONE}}/
├── <dir ou fichier>    # rôle en une ligne
└── <dir ou fichier>    # rôle en une ligne
```

---

## Points d'entrée

| Entrée | Fichier | Appelé par |
|---|---|---|
| <nom> | `<chemin>:<ligne>` | <route, commande, événement, autre zone> |

---

## Flux

<Le chemin nominal à travers la zone, en trois à six étapes, avec les fichiers traversés.>

---

## Pièges

<!-- Un symptôme suivi de sa cause, pas une consigne. C'est ici que vivent les zones sensibles
     de cette zone, pas dans le CODEMAP de la racine. -->

- `<chemin>` : <ce qui surprend, et pourquoi>

---

## Commandes propres à la zone

<!-- Seulement si elles diffèrent de celles de la racine. Sinon, supprime la section. -->

| But | Commande |
|---|---|
| Tester cette zone seule | `<cmd>` |
