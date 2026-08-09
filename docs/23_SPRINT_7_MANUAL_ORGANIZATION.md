# Sprint 7 — Manual Memory Organization

**Status:** **CLOSED / ACCEPTED** (2026-08-08)  
**Physical-device verification:** **PASSED** (real iPhone)  
**Depends on:** Sprint 3–6 — all **CLOSED / ACCEPTED**  
**Canonical roadmap:** `docs/13_IMPLEMENTATION_ROADMAP.md` § Sprint 7  

**Milestone:** Collections become a real, user-steerable memory graph — offline, no AI filing.

**Approved:** 2026-08-08 (reduced scope Phase A + B).  
**Completion report:** `reviews/sprint-07-completion-report.md`.  
**Sprint 8 plan (awaiting architecture approval):** `docs/24_SPRINT_8_COLLECTION_RESOLVER.md` — **no Sprint 8 code until approved.**

---

## Approved scope

### IMPLEMENT
- **Phase A — Assignment spine:** Needs Review → Move (+ Create & Move), Collection → Collection Move, multi-select, Undo, live counts
- **Phase B — Multi-context membership:** Add to Collection, Remove from Collection, Needs Review orphan invariant

### DEFER (backlog — not Sprint 7; still deferred after acceptance)
- **Phase C:** Pin, Archive, Merge, Collection aliases  
- **Phase D:** Favorites, advanced peek ranking  

Purpose: make the fundamental Collection membership model production-ready before Sprint 8 automates it.

---

## Membership semantics (LOCKED)

ScreenTidy is a **many-to-many** memory graph. A screenshot may belong to more than one Collection.

### MOVE TO COLLECTION (exclusive)

`[A, B]` → Move to `C` → `[C]`

- Removes **all** previous Collection memberships
- Destination becomes the only membership
- New rows use `source = user`

### ADD TO COLLECTION (additive)

`[A]` → Add to `B` → `[A, B]`

- Keeps existing memberships
- Adds destination with `source = user`
- Does **not** remove other Collections

### REMOVE FROM COLLECTION

`[A, B]` → Remove from `A` → `[B]`

- Removes only the selected Collection membership
- Does **not** delete the screenshot, Photos asset, OCR, FTS, or other memberships

### NEEDS REVIEW invariant (LOCKED)

Needs Review (`kind = unassigned`) is **not** an ordinary user Collection. It is the organization inbox.

1. After a deliberate user assignment to a **normal** Collection (Move or Add), the screenshot **leaves Needs Review**.
2. If a screenshot has **zero** normal Collection memberships (`kind != unassigned`), it **returns to Needs Review**.

This prevents silently orphaned screenshots.

---

## User authority (LOCKED)

Every Sprint 7 membership mutation initiated by the user persists:

`source = user`

Architectural invariant for Sprint 8:

> **Explicit user organization has higher authority than future automatic organization.**

Sprint 8 must be able to see that a user explicitly placed a screenshot. Sprint 7 does **not** implement Sprint 8 conflict resolution — only provenance.

Sprint 7 must **not** add: LLM, embeddings, AI classification, automatic Collection naming, OCR classification, semantic clustering, Collection Resolver, confidence thresholds, or automatic filing.

---

## UX (preserve approved shell)

### Needs Review → Move
Select one/many → **Move** → pick Collection (or **New Collection**) → leave Needs Review → destination updates → snackbar → **Undo**

### Collection → Collection Move
Same Move sheet; exclusive reassignment; multi-select; Photos/OCR/FTS untouched.

### Add to Collection
Distinct action and copy from Move. Example: in Japan Trip → **Add to Collection** → Flight Bookings → remains in both.

### Remove from Collection
Metadata-only. **Never** labeled Delete. Final normal membership → Needs Review. Photos untouched.

### Create & Move
Existing flow: Move → New Collection → name + emoji → create → assign → confirm. No AI names.

### Collection picker
Reuse sheet. Move: destinations + New Collection. Add: destinations only; skip meaningless “already in X for all selected.” Keep simple.

### Multi-selection
One, many, Select All. Do not assume identical memberships. Undo restores **per-screenshot** prior membership sets (full-graph snapshot).

### Live UI
Membership changes update Collection counts, galleries, Home counts/peeks, Needs Review count immediately. Persist across kill/relaunch.

---

## PhotoKit / OCR / Search / access (LOCKED)

- Organization is **metadata only** — never move/modify/delete/duplicate Photos assets
- Preserve `photos_local_identifier`, OCR text/status/version, FTS, screenshot metadata
- After Move/Add/Remove, Sprint 6 text Search must still find the screenshot (explicit regression test)
- Limited / Denied / inaccessible: **do not destroy organization**; reconnect when access returns (Sprint 4)

---

## Undo (LOCKED)

Undo restores the **exact previous membership graph**, not a naïve reverse-move.

Example: `[A, B]` → Move to `[C]` → Undo → `[A, B]` (not merely `[A]`).

Multi-select: each screenshot’s prior membership set restored (snapshot-based undo).

---

## Definition of Done

1. Needs Review → Collection assignment production-backed  
2. Single + multi-select Move works  
3. Create & Move works  
4. Collection → Collection Move works  
5. Add to Collection (multi-context)  
6. Remove from Collection  
7. Zero normal memberships → Needs Review  
8. Undo restores exact previous membership graph  
9. User mutations persist `source = user`  
10. Counts / galleries / peeks update immediately  
11. State survives relaunch  
12. PhotoKit assets untouched  
13. OCR survives organization  
14. FTS Search survives organization  
15. Limited/revoked access does not destroy organization  
16. No AI / automatic filing  
17. Phase C/D **not** implemented  
18. Automated tests pass  
19. Physical-device checklist provided  

---

## Physical-device acceptance checklist

| ID | Case | Expected |
|----|------|----------|
| A | NR → select one → Move to existing Collection | Leaves NR; in Collection |
| B | NR → select multiple → Move | All move |
| C | Move → New Collection | Created + assigned |
| D | Collection A → Move → B | A loses; B gains |
| E | In A → Add to B | In **both** A and B |
| F | In A+B → Remove from A | Remains in B |
| G | Remove final membership | Returns to Needs Review |
| H | Move `[A,B]` → C → Undo | Exactly `[A,B]` |
| I | Multi-select Move → Undo | Per-shot graphs restored |
| J | Move → Search OCR text | Still finds it |
| K | Kill/relaunch | Memberships persist |
| L | Revoke Photos → restore | Organization survives |
| M | Check Photos app | No assets moved/deleted/duplicated |

**Result:** **PASSED** (2026-08-08, real iPhone). Sprint 7 **CLOSED / ACCEPTED**.

---

## Non-goals

Phase C/D · Sprint 8 intelligence · UI redesign of Home/Search/tabs · Photos album mutation
