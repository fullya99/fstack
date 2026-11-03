# TODOS, {{PROJECT_NAME}}

> Quoi maintenant. Ce fichier ne garde que le futur. Ce qui est fait disparaît d'ici et vit
> au CHANGELOG.

## 🔄 État à la reprise, {{DATE}}

<!-- Bloc RÉÉCRIT à chaque clôture depuis l'état courant, jamais empilé. Quarante lignes au
     plus. C'est ce qui est lu en premier après un redémarrage à froid, il doit suffire à
     reprendre sans poser de question. Ce qui en sort a un propriétaire : un événement est déjà au
     CHANGELOG, un piège va dans sa fiche ou sa carte de zone, une tâche va dans la liste plus
     bas, une décision en ADR. Le récit ne se garde pas. -->

**Où on en est** : <2 à 4 lignes factuelles, ce qui marche, ce qui est en place>

**En cours** : <la tâche entamée et pas finie, avec les fichiers concernés, ou « rien »>

**Prochaine étape** : <la toute prochaine action concrète, quel fichier tu ouvres, quoi faire>

**À savoir avant de toucher** : <état instable, travail à moitié appliqué, piège du moment>

**Vérifier le terrain** : `git log --oneline -10 && git status -s` <remplacer par la commande qui prouve l'état annoncé ci-dessus : tests, build ou script de contrôle>

---

<!-- Pas de section « ce que cette session a produit », c'est du CHANGELOG. Pas de case cochée,
     une tâche faite se supprime. Pas de section « décidé », une décision va en ADR ou nulle part.
     Fichier entier : cible 150 lignes. -->

## 🔴 Bloqué

- [ ] <tâche>, bloquée par <quoi>, à débloquer en <comment>

## 🎯 Prochaines étapes

- [ ] <verbe à l'infinitif, plus une zone concrète : fichier, module ou commande>

## 🧹 Dette et améliorations

- [ ] <ce qu'on sait imparfait>, impact : <pourquoi ça compte>

## 💡 Idées non engagées

- <à purger sans état d'âme si ça ne prend pas>
