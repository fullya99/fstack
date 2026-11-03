<!-- contexte:convention
version: 5
profil: {{PROFIL}}
piliers: CODEMAP.md, TODOS.md, CHANGELOG.md
docs: {{DOCS}}
archives: {{ARCHIVES}}
langue: fr
-->

# CODEMAP, {{PROJECT_NAME}}

> Où ça se trouve, et qu'est-ce qui touche quoi.
> Dernière mise à jour : {{DATE}}

<!-- Cible 250 lignes, blocage à 400. Ce qui déborde descend dans une carte de zone. -->

**En une phrase** : <ce que fait ce projet, et pour qui>.

---

## Arborescence

```
<racine>/
├── <dir>/          # rôle en une ligne
├── <dir>/          # rôle en une ligne
└── <dir>/          # rôle en une ligne
```

<!-- Ne liste que ce qui porte du sens. Omets les dépendances, les builds, les caches. -->

---

## Modules

| Module | Chemin | Rôle | Fiche |
|---|---|---|---|
| <nom> | `<chemin>` | <une ligne> | [docs](docs/modules/<nom>.md) |

---

## Points d'entrée

| Entrée | Fichier | Déclenché par |
|---|---|---|
| <nom> | `<chemin>:<ligne>` | <commande, route, événement, cron> |

---

## Flux principal

<Le chemin nominal, en trois à six étapes, avec les fichiers traversés.>

1. `<fichier>` : <ce qui s'y passe>
2. `<fichier>` : <ce qui s'y passe>
3. `<fichier>` : <ce qui s'y passe>

---

## Dépendances externes

| Dépendance | Usage | Configuration | Où sont les identifiants |
|---|---|---|---|
| <service, API, base> | <à quoi ça sert> | `<var d'env ou fichier>` | <emplacement, **jamais la valeur**> |

---

## Commandes

| But | Commande |
|---|---|
| Installer | `<cmd>` |
| Lancer | `<cmd>` |
| Tester | `<cmd>` |
| Lint et format | `<cmd>` |
| Build | `<cmd>` |
| Déployer | `<cmd>` |

---

## Zones sensibles

<!-- Seulement ce qui n'appartient à aucune zone ni à aucune fiche. Un piège qui concerne une
     zone va dans sa carte. -->

- `<chemin>` : <généré, ne pas éditer à la main, ou effet de bord, ou convention non évidente>

---

## Zones

<!-- Un répertoire qui porte sa propre carte. Liste et POINTE, ne recopie rien. Vide sur un
     petit projet, c'est normal. -->

| Zone | Chemin | Sa carte | Ses règles |
|---|---|---|---|
| <nom> | `<chemin>` | [CODEMAP](<chemin>/CODEMAP.md) | `<chemin>/CLAUDE.md` ou « aucune » |

---

## Sous-projets

<!-- Monorepo uniquement. Un sous-projet porte ses trois piliers et se clôture à part. -->

| Sous-projet | Chemin | Sa carte |
|---|---|---|
| <nom> | `<chemin>` | [CODEMAP](<chemin>/CODEMAP.md) |
