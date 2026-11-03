# Déléguer à des profils d'agents

La session principale orchestre. Elle garde le cadrage, l'arbitrage, la décision irréversible et
la validation. Le reste part en profil, lecture comprise. Valable pour tout projet et tout langage.

## Les profils

| Profil | Modèle | Effort | Outils | Pour |
|---|---|---|---|---|
| `explorateur` | `haiku` | low | lecture et Bash | trouver, lire, inventorier, compter, résumer un fichier borné |
| `controleur` | `haiku` | low | lecture et Bash | lancer tests, linters et scripts de contrôle, rendre la sortie brute |
| `executant` | `sonnet` | low | tous | geste mécanique déjà décidé : renommage, patch fourni, régénération |
| `developpeur` | `sonnet` | medium | tous | implémenter un changement cadré, avec ses tests et sa doc |
| `chercheur` | `sonnet` | medium | web, lecture et outils MCP de recherche de la session | information externe, sourcée et datée |
| `expert` | `sonnet` | high | tous | cause racine inconnue, migration, sécurité, code délicat |
| `relecteur` | `sonnet` | high | sans écriture, Bash pour lancer des contrôles seulement | relecture adversariale d'un diff contre ses critères, toujours neuf |

Ils s'appellent `fstack:<profil>`. Le modèle est un alias, il ne fige aucune version.

## Choisir

Le profil le plus bas qui tient le critère de fin. Un échec repart une fois au cran du dessus, puis
l'orchestrateur reprend la main. Un modèle plus lourd en sous-agent se demande explicitement, il
n'est jamais le défaut.

Une sortie de `explorateur` ou de `controleur` se recoupe avant d'agir : on exige des chemins et des
chiffres, on relance un `grep` ou un `wc` sur ce qui engage la suite. Un profil bon marché qui
enchaîne les tours sur une tâche à plusieurs étapes finit par coûter plus qu'un cran au-dessus :
`haiku` pour un contrat fermé (trouver, compter, lancer), pas pour une enquête.

## Le brief

Quatre éléments, dans cet ordre :

1. La spec : ce qu'on veut, en quelques lignes.
2. Les chemins exacts : fichiers à lire, fichiers à écrire.
3. Le critère de fin : une commande qui passe, ou un fait observable.
4. La consigne « vise court ».

Un fait que l'orchestrateur a mesuré passe dans le brief avec sa commande et sa date. Sans elles,
il s'écrit « rapporté » et le profil le revérifie avant de bâtir dessus.

**Le paquet du relecteur.** Un `git diff` nu ne montre ni les fichiers neufs ni l'état de l'index.
L'orchestrateur prépare le paquet hors du dépôt et le donne par son chemin :

```bash
P=<scratchpad>/revue; mkdir -p "$P"
git status --porcelain > "$P/etat.txt"
git diff HEAD > "$P/diff.patch"
# diff --no-index rend 1 des qu'il y a une difference, donc xargs rend 123 sur un paquet correct :
# ce code ne juge rien, on compte les fichiers du paquet contre etat.txt.
git ls-files --others --exclude-standard -z | xargs -0 -r -I{} git diff --no-index /dev/null {} >> "$P/diff.patch"
git status --porcelain | cksum > "$P/empreinte.txt"   # l'arbre ne bouge plus pendant la revue
split -b 60000 "$P/diff.patch" "$P/tranche-"           # une lecture plafonne vers 25 000 tokens
```

Le brief nomme les invariants du projet à vérifier en premier (secrets, écritures distantes,
codes de retour, ce que `CLAUDE.md` interdit), avant la correction générale. À la fin, l'empreinte
se recalcule : si elle a changé, la revue a porté sur un autre arbre et se rejoue.

Le rapport revient en trois lignes, puis le détail demandé :

```
Fait : <ce qui est terminé>
Reste : <ce qui n'est pas fait>
Surpris : <ce que le brief ne prévoyait pas>
```

## Les limites

- Jamais deux agents sur les mêmes fichiers.
- Cinq agents en parallèle au plus.
- Un agent ne lance pas d'agent. `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` le garantit, il est recommandé.
- Un profil ne commite pas et ne pousse pas.
- Chaque profil porte `maxTurns: 200` : au-delà, Claude Code l'arrête et rend sa sortie comme
  partielle, reprenable. Le profil rend de lui-même un point d'étape vers 180 tours.
- Un profil qui écrit passe par les outils d'édition, jamais par un heredoc ou un `sed -i` en Bash.

## Régler la session principale

L'effort élevé se pose de l'une de ces deux façons :

```bash
/effort high                       # sauvegardé par modèle
```

```json
{ "effortLevel": "high" }
```

Le second va dans le `.claude/settings.json` du projet. Jamais `CLAUDE_CODE_EFFORT_LEVEL` : cette
variable passe aussi devant l'`effort` de chaque profil et écrase toute la graduation.

## Les alias selon la plateforme

Sur l'API Anthropic, `haiku` et `sonnet` suivent la dernière version de leur famille. Sur Bedrock,
Vertex et Foundry, ils pointent encore sur une version 4.x. Pour y retrouver la version voulue, on
épingle par variable d'environnement : `ANTHROPIC_DEFAULT_SONNET_MODEL`,
`ANTHROPIC_DEFAULT_HAIKU_MODEL` et leurs voisines.

## Sans sous-agents

Codex, Hermes et OpenClaw n'ont pas tous les sous-agents. La doctrine devient alors un découpage en
étapes, chacune avec son critère de fin vérifié avant de passer à la suivante, et la relecture se
fait dans une session neuve.
