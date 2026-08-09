# SPRINT 7 COMPLETION REPORT

**Sprint:** 07 — Manual Memory Organization (Phase A + B)  
**Date:** 2026-08-08  
**Status:** **CLOSED / ACCEPTED** (2026-08-08)  
**Physical-device verification:** **PASSED** (real iPhone)  
**Milestone:** Collections become a real, user-steerable memory graph — offline, no AI filing.

**Sprint 8 was NOT started during Sprint 7.**  
**Sprint 8 plan (docs only):** `docs/24_SPRINT_8_COLLECTION_RESOLVER.md` — awaiting architecture approval before implementation.

---

## Approved scope (locked)

### Implemented
- **Phase A — Assignment spine:** Needs Review / Collection Move (+ Create & Move), multi-select, Undo, live counts  
- **Phase B — Multi-context:** Add to Collection, Remove from Collection (repository APIs + tests), Needs Review orphan invariant, `source = user`

### Deferred (backlog — not shipped)
- **Phase C:** Pin, Archive, Merge, aliases  
- **Phase D:** Favorites, advanced peek ranking  

Plan: `docs/23_SPRINT_7_MANUAL_ORGANIZATION.md`

---

## What shipped

### Membership semantics
| Action | Behavior |
|--------|----------|
| **Move** | Exclusive — all prior memberships removed; destination only; `source = user` |
| **Add** | Additive — keeps other Collections; strips Needs Review when adding to a normal Collection |
| **Remove** | One Collection only; never deletes Photos/OCR/FTS; zero normal memberships → Needs Review |

### Needs Review invariant
- Deliberate user assignment to a normal Collection → leave Needs Review  
- Zero normal memberships → return to Needs Review (`source = user`)  

### Undo
- Snapshot-based restore of the **exact** prior membership graph (including multi-context and multi-select)

### UI (accepted shell)
- Collection Detail selection: **Move** · **Delete** (Add/Remove remain as repository capabilities for Sprint 8+)  
- Fullscreen viewer **Move**  
- Shared Move picker + Create & Move  
- Home Collection hold-to-drag reorder (`sort_order`)  

### Provenance for Sprint 8
- User mutations persist `source = user`  
- Explicit user organization outranks future automatic organization  
- `organizeIfNeeded` remains stub; no Resolver / AI in Sprint 7  

### Preserved
- PhotoKit metadata-only org (no album move/delete/duplicate except explicit user Photos delete)  
- Sprint 4 sync / access behavior  
- Sprint 5 OCR  
- Sprint 6 FTS Search  

---

## Automated tests

**30/30 passed** (`GRDBMemoryRepositoryTests` at acceptance), including Sprint 7 cases:
- Move exclusive + leaves Needs Review + `source = user`  
- Add multi-context + leaves Needs Review  
- Remove one keeps others; remove final → Needs Review  
- Undo restores exact multi-membership graph  
- Multi-select Move Undo restores per-screenshot graphs  
- Move/Add preserve OCR + FTS Search  
- Collection reorder persists across reload  

---

## Physical-device verification

**PASSED** on owner’s real iPhone (2026-08-08).

Owner confirmed:
- Sprint 7 manual organization flows work correctly  
- No blocking issues found  

Representative cases covered in acceptance (see plan checklist A–M): Move / Create & Move / multi-select / Needs Review invariant / Undo / Search survival / kill-relaunch / Photos untouched.

---

## Docs

- `docs/23_SPRINT_7_MANUAL_ORGANIZATION.md` — **CLOSED / ACCEPTED**  
- `docs/13_IMPLEMENTATION_ROADMAP.md` — Sprint 7 closed; Sprint 8 plan linked  
- `docs/README.md` — index updated  
- `docs/24_SPRINT_8_COLLECTION_RESOLVER.md` — **PLAN ONLY** (no implementation)

---

## STOP

Sprint 7 is **CLOSED / ACCEPTED**.  
Phase C/D remain deferred.  
**Do not implement Sprint 8** until the Collection Resolver plan is explicitly approved (intelligence architecture, privacy model, confidence strategy).
