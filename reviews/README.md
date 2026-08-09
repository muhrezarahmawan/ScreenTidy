# ScreenTidy Reviews

Project journal for ScreenTidy.

This folder captures **what we built**, **why we decided**, and **what we learned** — so context survives as the product grows.

---

## Purpose

| Document | Role |
|----------|------|
| `sprint-XX-review.md` | Per-sprint narrative (goals, outcomes, lessons) |
| `decisions.md` | Permanent decision log (historical memory of the product) |
| `README.md` | How to use this folder |

Reviews complement `/docs` (the product source of truth).  
`/docs` = what is true now.  
`/reviews` = how we got here and what we learned.

---

## When to create a sprint review

Create or update a sprint review:

1. **At sprint start** — draft with goals (status: In Progress)  
2. **During the sprint** — add major decisions as they lock  
3. **At sprint close** — fill Completed, Lessons, Next Sprint; set status: Complete  

Do **not** wait until memory fades. Prefer writing decisions the same day they lock.

---

## Sprint review template

Copy into `sprint-XX-review.md`:

```markdown
# Sprint Summary

**Sprint:** XX  
**Date:** YYYY-MM-DD  
**Status:** In Progress | Complete | Paused

---

## Goals

What was planned?

---

## Completed

What was successfully completed?

---

## Product Decisions

What product decisions were made? Why?

---

## UX Decisions

What visual or UX decisions were locked? Why?

---

## Engineering Decisions

Architecture · Patterns · Libraries · Tradeoffs

---

## Risks

Known risks · Technical debt · Future considerations

---

## Lessons Learned

What worked well? What should we improve next sprint?

---

## Next Sprint

Goals · Dependencies · Blockers
```

---

## Decision log workflow (`decisions.md`)

1. When a **major** product, UX, or engineering choice is locked, add an entry to `decisions.md`.  
2. Use a stable ID (`D-001`, `D-002`, …).  
3. Include: date, decision, alternatives considered, rationale, status (Locked / Superseded).  
4. If a decision changes later, **do not delete** the old entry — mark it Superseded and link the new ID.  
5. Sprint reviews should **reference** decision IDs rather than restating essays.

Major = architecture, IA, Home direction, navigation model, AI approach, privacy model, taxonomy vs contexts, etc.  
Minor implementation details stay in sprint reviews or code comments.
