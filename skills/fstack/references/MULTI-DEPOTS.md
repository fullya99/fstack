# MULTI-DEPOTS : plusieurs dépôts, une seule convention

> Chaque dépôt garde ses trois piliers. Ce qui change, c'est qui pointe vers qui, et où un savoir
> commun a le droit de vivre.

## Parent à sous-modules

Le parent pointe, il n'absorbe pas. Recopier la doc d'un enfant dans le parent crée deux versions
qui divergent en quelques sessions.

- Chaque enfant équipé porte son propre kit (`CODEMAP.md`, `TODOS.md`, `CHANGELOG.md`) et se
  clôture à part, dans son dépôt, sur sa branche.
- La carte du parent dit pour chaque sous-module s'il a son kit. Une ligne suffit :
  `ops/ : kit complet, voir ops/CODEMAP.md`.
- Le pointeur du parent est un commit de l'enfant. Quand l'enfant a avancé, le parent l'avance
  dans sa propre clôture, avec `git add <sous-module>`, et le dit au journal.
- Une session qui part du parent et touche un enfant clôture les deux niveaux, l'enfant d'abord.

Vérification : `git submodule status` ne montre ni `+` ni `-` devant un chemin dont la carte du
parent dit qu'il est à jour.

## Monorepo à zones

Un répertoire trop gros pour la carte racine reçoit sa propre carte, sans état propre. Le détail,
y compris la différence entre zone et niveau autonome, est dans `ZONES.md`. Un package qui a sa
propre vie porte les trois piliers et se traite comme un enfant ci-dessus.

## Plusieurs instances qui partagent un savoir

Cas de plusieurs machines ou agents qui travaillent sur le même domaine, chacun dans son dépôt.
Deux dossiers séparent ce qui est brut de ce qui est validé.

| Dossier | Qui y écrit | Statut |
|---|---|---|
| `kb/contrib/` | chaque instance, une fiche par contribution, signée et datée | brut, non vérifié |
| `kb/socle/` | l'opérateur seul, en promouvant une contribution | validé, fait foi |

Une instance lit `kb/socle/` comme source et dépose ses trouvailles dans `kb/contrib/`. Elle
n'édite jamais le socle. La promotion se fait par un commit de l'opérateur, qui relit la fiche et
la déplace avec `git mv`. Une contribution refusée part en `archives/` avec sa raison.

`CODEMAP.md` indique les deux dossiers et la règle d'écriture.

## Ce que `ctx-audit.sh` contrôle

Sections 6 et 11 de `bash "$SKILL/scripts/ctx-audit.sh"`, les chemins venant de `.gitmodules`.

- Un chemin sous un sous-module non initialisé n'est pas compté comme lien mort.
- Un enfant qui a les trois piliers, alors que `CODEMAP.md` ou `CLAUDE.md` du parent dit qu'il
  n'a pas de kit : alerte, la carte du parent est à corriger.
- Un pointeur du parent plus ancien que le dernier changement de `TODOS.md` de l'enfant :
  information, avec la commande `git add <sous-module>` pour l'avancer.
- Un sous-module non cloné se saute sans bruit.

L'audit ne contrôle ni `kb/contrib/` ni `kb/socle/`, la discipline d'écriture reste à l'opérateur.
