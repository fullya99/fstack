# CHANGELOG, {{PROJECT_NAME}}

> Ce qui a changé, pourquoi et comment revenir en arrière.
> Plus récent en haut. Une entrée par session utile, pas une par commit. Append-only : on ne
> réécrit pas le passé, on le corrige par une nouvelle entrée.

<!-- Une entrée tient en 25 lignes, le détail va dans une fiche docs/ et l'entrée pointe.
     Au-delà de 30 entrées, le journal tourne : les anciennes partent dans
     archives/changelog/AAAA-MM.md par ctx-rotation.sh, qui pose ici la ligne qui le dit. -->

---

## {{DATE}}, mise en place de la convention de contexte

**Quoi** : ajout de `CODEMAP.md`, `TODOS.md`, `CHANGELOG.md`, `docs/`, `archives/`.

**Pourquoi** : pouvoir repartir d'un contexte vide sans perdre d'information. Le dépôt devient la
source de vérité.

**Rollback** : supprimer les fichiers ajoutés. Aucun impact sur le code.

**Voir aussi** : `docs/README.md`, `archives/README.md`.
