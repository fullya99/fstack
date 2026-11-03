# HANDOFF : le test « prêt pour un contexte neuf »

> Repartir à froid est irréversible côté contexte, que ce soit par le `/clear` de Claude Code ou
> par le mécanisme équivalent d'un autre agent. Ce qui n'a pas été écrit est perdu. Cette page est
> la barrière de sécurité avant de le déclencher.

## Le test, en une phrase

> Si cette conversation disparaissait maintenant, une session neuve pourrait-elle reprendre le
> travail exactement là où il en est, sans poser de question à l'utilisateur ?

Tant que la réponse est non, la clôture n'est pas finie. Et ça ne se remplace pas par un résumé
plus long dans le chat, vu que le chat va disparaître.

---

## Simulation de reprise à froid

La seule vérification qui vaut vraiment, c'est de te relire comme si tu ne savais rien.

1. Rouvre `TODOS.md`, section « État à la reprise », et ne lis que ça.
2. Demande-toi quelle est ta toute prochaine action, concrètement, quel fichier tu ouvres.
   Si la réponse est claire, le bloc fait son travail. Si tu hésites, il manque une information,
   ajoute-la maintenant.
3. Ouvre `CODEMAP.md` et vérifie que les fichiers cités à l'étape 2 y figurent bien.
4. Vérifie qu'un piège rencontré cette session est écrit quelque part, dans la fiche `docs/` du
   module concerné ou dans `docs/pieges/` ou les zones sensibles du `CODEMAP.md` (un seul des deux par projet, `docs/pieges/` s'il existe). Sinon il sera re-découvert plus tard,
   au prix des mêmes erreurs.
5. Confronte `git status` et `git log -3` à ce que raconte le CHANGELOG.

Un écart trouvé ici est toujours un vrai défaut de clôture. Tu le corriges, tu ne le notes pas
pour plus tard.

---

## Checklist bloquante

### Exactitude
- [ ] Les 3 piliers reflètent l'état vérifié, pas l'état supposé.
- [ ] Aucune contradiction entre piliers. Le cas classique : TODOS annonce une tâche faite que
      CODEMAP décrit encore comme absente.
- [ ] Aucun chemin, commande ou ressource cité qui n'existe plus.
- [ ] Aucune affirmation connue-fausse laissée « pour plus tard ».

### Complétude
- [ ] Le bloc « État à la reprise » est réécrit à la date du jour.
- [ ] Tout travail entamé et pas fini a une tâche explicite dans TODOS, avec ses fichiers.
- [ ] Le travail à moitié appliqué est signalé : migration partielle, refactor interrompu,
      feature derrière un flag, fichier laissé dans un état intermédiaire.
- [ ] Chaque décision structurante prise cette session a son ADR dans `docs/decisions/`.
- [ ] Chaque piège rencontré est écrit, dans la fiche du module ou dans les zones sensibles du
      CODEMAP. C'est le gain le plus direct de la clôture.
- [ ] Chaque préférence exprimée par l'utilisateur est dans `CLAUDE.md`, et rien de volatile n'y
      a été ajouté au passage.
- [ ] Les modules et features touchés ont une fiche `docs/` à jour et indexée.

### Propreté
- [ ] Ce qui est obsolète est dans `archives/`, avec en-tête et ligne d'index.
- [ ] Aucune suppression silencieuse.
- [ ] Les statuts `🔴` de `docs/` ont été traités. Les `🟡` sont vérifiés ou datés d'aujourd'hui.
- [ ] `ctx-audit.sh --budget` ne rend aucun `[!!]`, chaque `[!]` a son geste ou sa tâche datée.
- [ ] Aucune section de session ni case cochée dans TODOS, ni état ni récit dans `CLAUDE.md`.

### Sécurité
- [ ] Aucun secret dans un fichier tracké : clé, token, mot de passe, URL signée.
- [ ] Les fichiers d'environnement restent ignorés.
- [ ] `git status` conforme à l'intention, rien d'oublié, rien de parasite.

### Multi-niveaux
- [ ] Chaque niveau touché a été mis à jour : racine, sous-projet, configuration partagée.
- [ ] Le parent pointe vers la doc des enfants, il ne l'a pas absorbée.
- [ ] Chaque zone touchée a sa carte à jour, et chaque zone est citée dans le CODEMAP racine.

### Ce qui prouve une case cochée

Une case se coche sur une preuve fraîche de cette session, jamais sur un souvenir.

| Affirmation | Preuve exigée | Ce qui ne suffit pas |
|---|---|---|
| un contrôle est vert | son code nu, lu sur la commande elle-même | un `tail` en bout de tube, qui rend 0, ou un code 2 (rien regardé) |
| la doc dit vrai | `ctx-verite.sh --strict` rend 0 | une relecture de mémoire |
| c'est commité | `git log -1 --stat` liste les fichiers de la clôture | `git status` propre (un autre commit a pu les emporter) |
| c'est poussé | `git rev-parse HEAD` égale `git rev-parse @{u}` | un push lancé dont on n'a pas lu le code |
| un agent a fini | son diff relu, sa commande de fin rejouée | son rapport « Fait » |
| rien n'utilise X | la commande qui l'aurait trouvé, et ce qu'elle a balayé | un `grep` qui saute les fichiers ignorés par git |
| l'opérateur a validé | sa phrase, sur ce point précis | un « ok » donné sur autre chose |

### Les excuses qui font sauter une clôture

| Ce qu'on se dit | Ce qui est vrai |
|---|---|
| « Je l'ai vu passer tout à l'heure » | Une sortie vue avant la dernière édition ne prouve rien sur l'état actuel |
| « C'est une petite session, pas besoin » | La phase 4 et la phase 5 se jouent toujours, une ligne suffit |
| « Je le noterai à la prochaine clôture » | Il n'y a pas de prochaine fois, il y a un redémarrage qui l'efface |
| « Le sous-agent a dit que c'était bon » | Son rapport est une affirmation, le diff est la preuve |

---

## Anti-patterns de passation

| Anti-pattern | Pourquoi ça casse | À la place |
|---|---|---|
| « Continuer le refactor » | Au retour, personne ne sait où il en était | « Finir l'extraction de `parse()` vers `lib/parser.ts`, 3 appelants restent à migrer : `a.ts:12`, `b.ts:88`, `c.ts:40` » |
| Résumé chronologique de la session | La suite ne se déduit pas du récit | Un état : ce qui marche, ce qui est en cours, la prochaine action |
| Doc écrite depuis le souvenir | Le souvenir garde un état intermédiaire, pas l'état final | Vérifier le fichier, la commande, le service |
| Redater une fiche sans la relire | `docs/` devient un piège, le lecteur fait confiance à tort | Relire, corriger, puis dater |
| Empiler les « État à la reprise » | Le lecteur ne sait plus lequel fait foi | Un seul bloc, réécrit |
| Tout empiler dans `CLAUDE.md` | Il est chargé à chaque session, le signal se noie et le contexte se paie tout le temps | Une décision en ADR, un piège dans la fiche du module, une préférence seulement si elle est vraie en permanence |
| Garder le faux « pour plus tard » | Il n'y a pas de plus tard, il y a un redémarrage | Corriger ou archiver, maintenant |
| Reporter la clôture « à la fin » | La fin arrive par manque de contexte, au pire moment | Clôturer quand le travail est cohérent, pas quand le contexte est plein |
| Empiler le bloc de reprise en journal | Le lecteur paie 40 000 tokens avant de savoir quoi faire | Réécrire depuis l'état courant, 40 lignes, classer ce qui sort |
| Un compte-rendu de session dans TODOS | TODOS ne garde que le futur | L'entrée va au CHANGELOG |
| Tenir le seuil en effaçant un piège | Le piège revient au prix d'une session | Il descend dans la carte de sa zone ou la fiche du module |

---

## Quand clôturer

Avant tout redémarrage à froid volontaire, évidemment. Mais aussi quand une unité de travail
cohérente est terminée, même si la session continue. Quand le contexte approche de la saturation, avant que la
qualité baisse et pas après. Avant une interruption longue. Avant de passer à un sujet sans rapport.

Une clôture précoce coûte quelques minutes. Une clôture manquée coûte une re-découverte complète,
et parfois du travail refait.

---

## Au retour, la reprise

Ordre de lecture, c'est le mode RELANCE du skill.

1. `CLAUDE.md`, les règles et les préférences durables.
2. Lecture partielle, jamais un pilier entier :

   ```bash
   awk '/^## /{n++} n<=1' TODOS.md      # le bloc de reprise, rien d'autre
   grep -n '^## ' CODEMAP.md            # le plan, puis la section utile
   awk '/^## /{n++} n<=3' CHANGELOG.md  # les 3 dernières entrées
   ```
3. Puis la carte de la seule zone concernée par la tâche.
4. Les fiches `docs/` des seuls modules concernés, et l'ADR si tu reviens sur un choix tranché.
5. `git log --oneline -10` et `git status -s`, pour confronter au réel.

Ne charge pas `archives/`. Ne lis pas tout `docs/`. Ne relis pas tout le CHANGELOG. La reprise
doit coûter peu de contexte, sinon elle annule le bénéfice du redémarrage.

Restitue en dix lignes maximum : où on en est, ce qui est en cours, la prochaine étape, les
pièges. Toute incohérence entre la doc et le dépôt se corrige avant de coder. C'est le symptôme
d'une clôture précédente incomplète, et c'est le seul moment où on a pas encore payé cher pour
la réparer.
