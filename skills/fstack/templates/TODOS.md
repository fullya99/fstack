# TODOS, {{PROJECT_NAME}}

> What now. This file keeps only the future. What is done leaves here and lives in the
> CHANGELOG.

## 🔄 Resume state, {{DATE}}

<!-- Block REWRITTEN at every debrief from the current state, never stacked. Forty lines at
     most. It is the first thing read after a cold restart, and it must be enough to resume
     without asking a question. What leaves it has an owner: an event is already in the
     CHANGELOG, a pitfall goes in its page or its zone map, a task goes in the list below, a
     decision goes in an ADR. The story is not kept. -->

**Where we are**: <2 to 4 factual lines, what works, what is in place>

**In progress**: <the task started and not finished, with the files involved, or "nothing">

**Next step**: <the very next concrete action, which file you open, what to do>

**To know before touching**: <unstable state, half-applied work, the pitfall of the moment>

**Check the terrain**: `git log --oneline -10 && git status -s` <replace with the command that proves the state announced above: tests, build or check script>

---

<!-- No "what this session produced" section, that is CHANGELOG. No ticked box, a finished task
     is deleted. No "decided" section, a decision goes in an ADR or nowhere.
     Whole file: aim for 150 lines. -->

## 🔴 Blocked

- [ ] <task>, blocked by <what>, to unblock by <how>

## 🎯 Next steps

- [ ] <verb in the imperative, plus a concrete area: file, module or command>

## 🧹 Debt and improvements

- [ ] <what we know is imperfect>, impact: <why it matters>

## 💡 Uncommitted ideas

- <purge without regret if it does not catch on>
