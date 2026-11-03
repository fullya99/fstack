# Où ranger ce qui sort de la racine

Chargé en phase 3 et en phase 5. C'est la partie qui fait le travail : sortir du fichier racine
tout ce qui n'a pas à y être. Vérifié le 2026-08-23 sur `code.claude.com/docs`.

## Pourquoi ça marche

Le fichier racine est chargé **à chaque session, en entier, avant ta première question**. Chaque
ligne y est payée pour toujours, qu'elle serve ou non. Et le coût n'est pas que le prix des
tokens : au-delà de 200 lignes la doc officielle annonce une baisse d'obéissance, et à 40 000
caractères l'outil affiche un avertissement de performance.

D'où l'idée : le fichier racine est de la mémoire vive, le reste est du disque. Sortir un bloc ne
le supprime pas, ça le déplace vers quelque chose qui ne charge que quand il sert.

Encore faut-il choisir la bonne sortie. Il y en a trois, elles ne se valent pas.

## Les quatre étages

| Étage | Où | Quand ça charge | Ce que ça coûte en permanence |
|---|---|---|---|
| 1. Racine | `CLAUDE.md` | chaque session, toujours | le fichier entier |
| 2. Règle liée à des chemins | `.claude/rules/<sujet>.md` avec `paths:` | quand l'agent touche un fichier qui matche | rien |
| 3. Skill | `.claude/skills/<nom>/SKILL.md` | le corps, quand le skill sert | le `name` et la `description`, rien de plus |
| 4. Fiche | `docs/<sujet>.md`, lien nu depuis la racine | si l'agent décide d'ouvrir le lien | rien |

**`@fichier` n'est pas un étage.** Un import colle le contenu dans l'étage 1, au démarrage,
récursivement jusqu'à quatre sauts. Découper un `CLAUDE.md` en imports n'économise pas un octet.
C'est le contresens le plus répandu sur le sujet, la demande de chargement paresseux a été fermée
en « not planned », et la doc elle-même s'est contredite là-dessus assez longtemps pour qu'un
ticket soit ouvert. Si tu vois des imports dans un fichier que tu audites, dis à l'opérateur qu'ils
ne l'allègent pas.

## Comment choisir

Une question, dans cet ordre, et tu t'arrêtes à la première qui répond oui.

1. **Est-ce vrai partout, tout le temps, quel que soit le fichier ouvert ?** Étage 1. Il reste.
2. **Est-ce que ça ne vaut que pour certains fichiers ou certains dossiers ?** Étage 2.
3. **Est-ce une procédure en plusieurs étapes, qu'on refait de temps en temps ?** Étage 3.
4. **Sinon**, c'est du savoir de référence. Étage 4.

## Le classement des sorties, et pourquoi il compte

Les trois sorties ne sont pas interchangeables, et c'est le point le plus important de cette fiche.

**L'étage 2 est le meilleur.** La règle se charge toute seule, au bon moment, sans que l'agent ait
à décider quoi que ce soit. Un `paths: ["src/api/**/*.ts"]` et la règle apparaît quand il ouvre un
fichier d'API, jamais avant.

**L'étage 3 vient ensuite.** Le chargement dépend d'un jugement de l'agent sur la `description`,
donc il peut rater. Mais la description reste en contexte, donc au moins il sait que le skill
existe.

**L'étage 4 est le plus faible.** Un lien nu ne garantit rien du tout. L'agent le voit, et il
choisit de l'ouvrir ou pas, selon ce qu'il croit avoir besoin de savoir.

La conséquence pratique : **une règle qui doit être appliquée ne va jamais à l'étage 4.** Elle va
en 2 ou en 3. L'étage 4 porte ce qu'on consulte, du contexte, une décision passée, un piège
documenté, pas une contrainte qui doit tenir.

Si tu ne sais pas faire tenir une contrainte à l'étage 2 ou 3, dis-le. C'est un cas où elle reste
à la racine, même si elle allonge le fichier. Une contrainte perdue coûte plus cher que dix lignes.

## Ce que chaque lecteur sait faire

| Étage | Claude Code | Codex | Hermes | OpenClaw |
|---|---|---|---|---|
| 2, règle liée à des chemins | oui | non | non | non |
| 3, skill | oui | oui, `.agents/skills/` | oui | oui |
| 4, fiche liée | oui | oui | oui | oui |

**L'étage 2 n'existe que chez Claude Code.** Sur un dépôt lu par plusieurs agents, une règle qui y
part disparaît pour les autres. Deux façons de traiter ça, et c'est à l'opérateur de trancher, pas
à toi : soit la règle est assez importante pour rester à la racine où tout le monde la voit, soit
elle part à l'étage 2 et le fichier racine garde une ligne qui dit qu'elle existe.

## Écrire un lien qui sert à quelque chose

Un lien nu ne dit pas quand l'ouvrir, donc il ne s'ouvre pas.

Ce qui ne marche pas :

```markdown
Voir aussi `docs/migrations.md`.
```

Ce qui marche, une table où chaque ligne dit la situation avant de donner le chemin :

```markdown
| Quand | Fiche |
|---|---|
| Tu ajoutes ou modifies une migration | `docs/migrations.md` |
| Un test d'intégration échoue en CI mais passe en local | `docs/ci-flaky.md` |
```

La colonne de gauche est ce qui fait ouvrir la fiche. Sans elle, la table n'est qu'une liste de
fichiers, et elle sera ignorée.

Même chose à l'étage 3 : c'est la `description` du skill qui décide de son chargement, elle dit
quand appeler, pas seulement ce que le skill fait.

## Combien de fiches

Une fiche par sujet, et un sujet c'est ce qu'on a en tête en même temps. Deux blocs qui parlent des
migrations vont dans la même fiche, même s'ils viennent de deux endroits du fichier racine.

Au-delà de 150 lignes, coupe en deux. En dessous de 15, ne crée pas la fiche : ces lignes rejoignent
une fiche voisine, ou elles restent à la racine. Une fiche de dix lignes coûte plus en navigation
qu'elle ne rapporte.

Et avant de créer quoi que ce soit, regarde ce qui existe. Un contenu déjà écrit dans un `README`,
une fiche ou un ADR ne part pas en fiche neuve, il devient un lien vers l'existant.
