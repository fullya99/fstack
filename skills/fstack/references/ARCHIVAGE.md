# ARCHIVAGE : la règle qui garde la doc propre

> Une doc ne pourrit pas parce qu'on écrit trop peu. Elle pourrit parce qu'on laisse vivre le
> faux à côté du vrai. `archives/` existe pour qu'on puisse retirer sans hésiter. Le contenu
> obsolète est déplacé, jamais détruit, donc l'archiver ne coûte rien.

## Les deux invariants

**Aucune suppression silencieuse.** Ce qui a compté a le droit d'être retrouvé, avec la date et
la raison de sa mise à l'écart.

**`archives/` n'est jamais une source de vérité.** Ça veut dire deux choses : jamais lu en
reprise, jamais cité depuis une fiche vivante. On ne s'en sert pas pour répondre à une question
sur l'état actuel, uniquement sur demande explicite d'archéologie. `ctx-audit.sh` voit désormais
les deux cas.

Les deux règles se tiennent. C'est parce qu'on n'y lit jamais rien qu'on peut y jeter généreusement.

---

## Arbre de décision

À appliquer sur tout contenu suspect : fiche, procédure, script, plan, proposition, règle durable.

```
Le contenu est-il faux, périmé ou remplacé ?
├── NON → tu ne touches à rien.
└── OUI
    ├── Est-ce un FICHIER entier devenu inutile ou faux ?
    │   ├── OUI → ARCHIVER, voir « Le geste, en une commande ». Le critère porte sur les
    │   │         références entrantes : pour chaque référence au fichier, est-elle opérative,
    │   │         quelqu'un en a besoin pour agir maintenant, ou est-elle historique, un
    │   │         commentaire qui raconte la provenance ? On archive quand toutes les
    │   │         références restantes sont historiques. Testable par un `git grep`,
    │   │         contrairement à « faux, périmé ou remplacé » qui reste un jugement.
    │   └── NON → c'est une SECTION d'un fichier encore utile
    │             → CORRIGER SUR PLACE, noter au CHANGELOG.
    │               On n'archive pas un fichier vivant pour une section fausse.
    ├── Est-ce une RÈGLE DURABLE (entrée de CLAUDE.md) ?
    │   └── → SUPPRIMER. Pas d'archivage.
    │         Une règle fausse est pire qu'absente. Sa trace va au CHANGELOG si utile.
    ├── Est-ce un ADR supersédé ?
    │   └── → RESTE EN PLACE, statut « Superseded par ADR-00NN ».
    │         Seule exception à l'archivage, un ADR vaut par son historicité.
    ├── Est-ce une TÂCHE faite ou abandonnée (TODOS.md) ?
    │   └── → SUPPRIMER de TODOS. Le fait accompli vit au CHANGELOG.
    ├── Est-ce une ENTRÉE de journal, vraie mais ancienne ?
    │   └── → ROTATION, jamais réécrite ni résumée. Voir plus bas.
    └── Est-ce une RÉFÉRENCE morte (lien, chemin, ressource supprimée) ?
        └── → CORRIGER si un remplaçant existe, sinon RETIRER en le disant.
```

Ce que tu ne fais jamais : laisser un `TODO: cette section est fausse` dans une doc vivante,
garder « au cas où », commenter au lieu de déplacer, supprimer un fichier documentaire sans trace.

---

## Le geste, en une commande

Deux temps, jamais un seul.

```bash
bash "$SKILL/scripts/ctx-archive.sh" --verifier <chemin>
bash "$SKILL/scripts/ctx-archive.sh" <chemin> --raison "..." --remplace-par "..."
```

`--dry-run` annonce sans écrire. `--force` passe outre un lien vivant, il ne se prend qu'en
connaissance de cause.

Le premier appel n'écrit rien, il classe les références entrantes et dit si un lien markdown
vivant bloque l'archivage. Le second fait tout, dans l'ordre.

1. Il reclasse les références entrantes et refuse s'il reste un lien markdown vivant vers le
   fichier, ce lien casserait au déplacement.
2. Il déplace par `git mv`, l'historique du fichier reste suivi.
3. Il pose l'en-tête de provenance.
4. Il résout les liens relatifs du fichier déplacé, depuis la racine du dépôt. Le chemin
   d'origine est réinjecté sous le préfixe d'archive, la profondeur change, remonter avec des
   `../` ne suffit pas, il faut redescendre depuis la racine.
5. Il ajoute la ligne d'index dans `archives/README.md`.
6. Il vérifie par `git grep` que plus aucune occurrence de l'ancien chemin ne subsiste hors des
   archives, et sort en erreur sinon.

Cette dernière étape est la porte qui manquait. Le geste à la main faisait quatre étapes, et la
quatrième, la ligne d'index, sautait le plus souvent, sans que rien ne le signale.

Variante `--resume <fichier>` : le fichier garde sa place sous forme de résumé, le texte intégral
part en archive. `<fichier>` est posé à l'ancien chemin, et `{{ARCHIVE}}` y devient le chemin de
l'archive. Les références entrantes restent valides, elles ne bloquent donc pas, et la
vérification finale contrôle que le résumé est en place. C'est l'appel de `ctx-rotation.sh --plans`.

Le script refuse d'archiver un pilier (`CODEMAP.md`, `TODOS.md`, `CHANGELOG.md`, `CLAUDE.md`) et
un index (`docs/README.md`, `archives/README.md`). Une section fausse d'un pilier se corrige sur
place, une règle durable devenue fausse se supprime, voir l'arbre de décision.

---

## Où va le fichier archivé

```
archives/<AAAA-MM>/<chemin d'origine complet>
```

| Origine | Destination |
|---|---|
| `docs/modules/auth-legacy.md` | `archives/2026-08/docs/modules/auth-legacy.md` |
| `scripts/deploy-v1.sh` | `archives/2026-08/scripts/deploy-v1.sh` |
| `docs/ops/migration-mongo.md` | `archives/2026-08/docs/ops/migration-mongo.md` |
| `CHANGELOG.md`, entrées d'août | `archives/changelog/2026-08.md` (rotation, pas `git mv`) |

Pourquoi ce schéma. Le bucket daté évite les collisions quand un même chemin est archivé
plusieurs fois dans la vie du projet. Le chemin d'origine préservé rend la provenance lisible
sans avoir à ouvrir le fichier.

Utilise toujours `git mv`, pas un copier suivi d'un supprimer. L'historique du fichier reste suivi.

---

## En-tête d'archive, obligatoire

Inséré tout en haut du fichier déplacé, avant son titre.

```markdown
> ⚠️ **ARCHIVÉ le 2026-08-13**, document non maintenu, gardé pour l'historique.
> **Origine** : `docs/modules/auth-legacy.md`
> **Raison** : le flux de session par cookie a été remplacé par OAuth. La procédure décrite
> ne marche plus depuis la refonte du 2026-08-13.
> **Remplacé par** : `docs/modules/auth.md` (ou « aucun remplaçant, la brique n'existe plus »)
> **Ne pas utiliser comme source de vérité.**
```

Trois règles de forme.

Les chemins sont notés depuis la racine du dépôt, en `code`, jamais en lien relatif. Un fichier
déplacé casse tous ses liens relatifs, et un lien mort dans une archive, c'est un piège de plus.

La raison est explicite et vérifiable. « Obsolète » ne renseigne personne. « Remplacé par X suite
à la refonte du <date> » permet de décider si l'archive a encore un intérêt.

Si la fiche est archivée sans remplaçant, dis-le. C'est une information en soi.

---

## L'index `archives/README.md`

Sans index, `archives/` devient un débarras que personne ne fouille, et le contenu archivé est
perdu pour de bon. Autant l'avoir supprimé.

```markdown
| Archivé le | Origine | Emplacement | Raison | Remplacé par |
|---|---|---|---|---|
| 2026-08-13 | `docs/modules/auth-legacy.md` | `archives/2026-08/docs/modules/auth-legacy.md` | remplacé par OAuth | `docs/modules/auth.md` |
```

Plus récent en haut. Une ligne par élément, ajoutée dans le même mouvement que le déplacement.
Un fichier présent dans `archives/` mais absent de l'index est un défaut, `ctx-audit.sh` le signale.

---

## L'histoire froide, la rotation des journaux

Une entrée ancienne de CHANGELOG n'est pas fausse, elle est froide. `archives/` est le seul
endroit que la convention ne lit jamais en reprise, c'est exactement la propriété qu'on cherche
pour du contenu vrai mais qui ne sert plus à décider.

`$SKILL/scripts/ctx-rotation.sh` garde les 30 entrées les plus récentes d'un journal et déplace
les autres dans `archives/<journal>/AAAA-MM.md`, groupées par mois de l'entrée. Un en-tête
`ARCHIVÉ` par fichier de mois créé, jamais par entrée. Une ligne d'index dans
`archives/README.md` par fichier créé. Lance-le en `--dry-run` d'abord, il est idempotent.

Il reconnaît les trois formats de la clé `journal:` du bloc de convention : `date-titre`
(`## AAAA-MM-JJ`), `keep-a-changelog` (`## [x.y.z] - AAAA-MM-JJ`) et `crochets`
(`[AAAA-MM-JJ] [TYPE] texte`, une ligne par entrée ou une ligne suivie de son corps). Sans
déclaration, il détecte le format et le dit. Vaut pour tout journal de ces formats, pas
seulement `CHANGELOG.md`.

Deux garde-fous. Un journal rangé du plus ancien au plus récent est refusé, code 3, parce que
la rotation garderait les plus vieilles entrées et archiverait les plus récentes. Un mois qui
dépasserait 1 500 lignes se coupe en `AAAA-MM.md`, `AAAA-MM-2.md`, et ainsi de suite, le plus
ancien dans le rang le plus bas, chaque fichier indexé. `--plafond` règle cette limite.

Pas de `git mv` ici, c'est un découpage de contenu à l'intérieur d'un fichier, la seule
exception à la règle du `git mv` de cette page.

### Les plans exécutés

`ctx-rotation.sh --plans [--root <chemin>] [--dry-run]` traite `plans/*.md`. Un plan est exécuté quand l'une de ces marques
existe : une ligne `Statut : terminé` (ou la bannière `PLAN EXÉCUTÉ`) dans ses 30 premières
lignes, sans négation, ou une ligne de `TODOS.md` qui cite `plans/<nom>.md` avec « terminé »,
« exécuté » ou une case cochée. Un plan exécuté de plus de 20 lignes devient un résumé de 20
lignes au plus à son chemin d'origine : titre, objectif, registre des écarts, commits. Le texte
intégral part dans `archives/AAAA-MM/plans/<nom>.md` par `ctx-archive.sh --resume`, avec son
en-tête et sa ligne d'index. Le chemin ne change pas, les références entrantes restent valides.
Un plan déjà résumé (marqueur `plan-resume`) ou de 20 lignes ou moins n'est pas touché. Le texte
intégral garde tout, y compris les cases restées ouvertes.

---

## Ce qui n'a rien à faire dans `archives/`

`archives/` documente l'histoire de la connaissance du projet, pas ses déchets.

- ❌ du code mort, git le conserve déjà, tu le supprimes et c'est tout,
- ❌ des dépendances, builds, caches, exports volumineux, ce n'est pas de la doc,
- ❌ des secrets même expirés, ça se révoque, ça ne s'archive pas,
- ❌ des brouillons jamais publiés, ils n'ont jamais fait autorité, il n'y a rien à tracer,
- ❌ des règles durables devenues fausses, voir l'arbre de décision.

Règle simple : tu archives ce qui a été considéré comme vrai et ne l'est plus. La rotation des
journaux est le second cas, et le seul, où `archives/` reçoit du vrai. L'en-tête dit lequel des deux
un fichier est, parce qu'un lecteur en archéologie n'a pas à le deviner.

---

## Y retourner, sans tout charger

`archives/` ne se lit jamais par défaut. S'il n'existe aucun chemin explicite vers ce
répertoire, l'interdiction de lecture en reprise revient à perdre ce qu'on prétend garder.

```bash
bash "$SKILL/scripts/ctx-archeo.sh" <motif>              # cherche, rend provenance puis extraits
bash "$SKILL/scripts/ctx-archeo.sh" --liste               # inventaire de ce qui est archivé
bash "$SKILL/scripts/ctx-archeo.sh" --fichier <chemin>    # la provenance d'une archive précise
```

Il rend toujours la provenance AVANT l'extrait, jamais l'inverse, pour qu'on ne prenne pas une
archive pour une vérité courante. Il distingue le froid du faux : une entrée de rotation était
vraie à sa date, un fichier archivé par `ctx-archive.sh` a cessé d'être vrai. La sortie est
bornée par `--max`, 20 occurrences par défaut.

Pourquoi pas un `grep` nu sur `archives/`. Il rend une ligne sans son en-tête, on prend alors du
froid pour du courant sans le savoir. Et sur une archive de journal de plusieurs milliers de
lignes, il déverse plus qu'il ne rend.

---

## Purge des archives

Les archives se relisent une fois par an environ, ou quand le répertoire devient volumineux.

Une archive dont plus rien ne dépend, et dont le sujet a totalement disparu, peut être supprimée
pour de bon. Git en garde l'histoire, et le message de commit de la suppression joue le rôle du
certificat de destruction attendu en gestion documentaire, il dit quoi, quand et pourquoi.

La ligne d'index correspondante reste, avec la mention `supprimé le AAAA-MM-JJ`. L'index est la
seule chose qui ne se purge jamais.

Aucune purge automatique. C'est une décision explicite, jamais un effet de bord d'une clôture.
