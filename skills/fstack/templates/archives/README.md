# Archives, {{PROJECT_NAME}}

> ⚠️ **Rien ici n'est une source de vérité.** Ce répertoire garde deux choses, ce qui a été vrai
> et ne l'est plus, et ce qui est encore vrai mais froid, les entrées anciennes des journaux mises
> de côté par rotation. L'en-tête de chaque fichier dit lequel des deux il est. On ne lit rien ici
> en reprise de session, on ne le cite pas depuis une fiche vivante. Uniquement sur demande
> explicite d'archéologie.
>
> La documentation à jour est dans `docs/` et dans les 3 piliers à la racine.

## Règles

**Aucune suppression silencieuse.** Un document retiré est déplacé ici, jamais effacé.

**Emplacement** : `archives/<AAAA-MM>/<chemin d'origine complet>`. Le bucket daté évite les
collisions dans le temps, le chemin préservé rend la provenance lisible.

**Déplacement avec `git mv`**, pour garder l'historique du fichier.

**En-tête obligatoire** en tête du fichier archivé :

```markdown
> ⚠️ **ARCHIVÉ le AAAA-MM-JJ**, document non maintenu, gardé pour l'historique.
> **Origine** : `<chemin d'origine>`
> **Raison** : <explicite et vérifiable, pas seulement « obsolète »>
> **Remplacé par** : `<chemin>` (ou « aucun remplaçant »)
> **Ne pas utiliser comme source de vérité.**
```

Les chemins sont notés depuis la racine du dépôt, jamais en lien relatif. Un fichier déplacé
casse ses liens relatifs.

**Ne vont pas ici** : le code mort (git le garde), les builds et caches, les secrets même
expirés, les brouillons jamais publiés, les règles durables devenues fausses (supprimées), les ADR supersédés
(ils restent en place, marqués).

## Y chercher quelque chose

```bash
bash "$SKILL/scripts/ctx-archeo.sh" <motif>          # provenance et extraits, sortie bornée
bash "$SKILL/scripts/ctx-archeo.sh" --liste          # inventaire, une entrée par fichier
```

Pas un `grep` nu : il rend une ligne sans son en-tête, donc on prend une entrée froide pour une
vérité courante.

## Index

| Archivé le | Origine | Emplacement | Raison | Remplacé par |
|---|---|---|---|---|
| | | | | |

<!-- Plus récent en haut. Une ligne ajoutée dans le même mouvement que le déplacement.
     Un fichier présent dans archives/ mais absent de cet index est un défaut. -->
