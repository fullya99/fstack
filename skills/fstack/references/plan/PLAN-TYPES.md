# The eight plan types

The type is chosen in phase 0, without reading code. It decides the research angle and the
sections the plan adds to its common skeleton.

| Type | Priority research | Extra sections | Typical pitfall |
|---|---|---|---|
| Feature | state of the art of the practice, the API of the libs touched | interface contract, edge cases | the solution is described before the expected behavior is written |
| Fix | the documented behavior of the version in place, known issues | reproduction, root cause, non-regression | the symptom is fixed, the cause remains |
| Migration | release notes between the starting version and the target, breaking changes | inventory of call sites, cutover order, rollback | a call site is discovered midway |
| Refactor | nothing, unless the targeted abstraction comes from elsewhere | behavior parity before and after, frozen scope | the scope grows along the way |
| Infrastructure and deployment | the provider's docs, costs, quotas | what is destroyed, what is reversible, order of operations | an irreversible step goes through without confirmation |
| Documentation and content | the source of truth of what is being documented | who reads, what they already know, what they must be able to do afterward | the intent is documented, not what exists |
| Investigation | broad, it is the heart of the work | the question to settle, what would count as an answer, the budget | the investigation has no stopping criterion |
| Non-code | the subject's own domain, never a technical axis | who decides, who executes, when it is done | a technical plan is written for a subject that is not technical |

## Feature

Phase 3 asks one more question than the other types: the edge case we choose to cover or exclude.
Phase 4 writes the interface contract before the design, not after. A plan that skips this section
describes code without saying what it must produce.

## Fix

Phase 2 starts by reproducing the bug before exploring, otherwise the exploration goes nowhere. The
root cause is named by file and line, not by hypothesis. The non-regression section lists the test
that should have failed before the fix.

## Migration

Phase 1 first looks for the release notes between the starting version and the target, before any
other axis. Phase 2 inventories every real call site, one by one, before the cutover order is
written. A migration plan with no rollback log is not one.

## Refactor

No external research unless the targeted abstraction comes from another project or a pattern
documented elsewhere. Phase 3 locks the scope in plain words and phase 4 freezes behavior parity
before and after as the end criterion.

## Infrastructure and deployment

Phase 1 looks for the provider's docs first, plus real costs and quotas. Phase 4 orders the
operations, separating what is reversible from what is not, and any irreversible step needs
explicit confirmation before it starts.

## Documentation and content

Phase 0 identifies who will read and what they already know, before looking up anything. Phase 2
explores the real code or product, not the project's intentions. The plan documents what exists,
not what it was meant to do.

## Investigation

No implementation plan, a research plan. Phase 3 sets the precise question to settle and the time
budget allotted, otherwise the investigation has no end. "What would count as an answer" is decided
before searching, not after.

## Non-code

Phases 1 and 2 change in nature: research covers the subject's domain, exploration covers the
project's existing documents and decisions, not a git repo. The plan replaces the technical design
with who decides, who executes, and when it is done.

## A plan spanning two types

A task can belong to two types at once, a migration that touches infra for example. In that case
take the more constraining type for the research angle, and add the extra sections of both types.
