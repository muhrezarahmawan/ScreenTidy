# SPRINT 6 COMPLETION REPORT

**Sprint:** 06 — Search (FTS Wired)  
**Date:** 2026-08-08  
**Status:** **CLOSED / ACCEPTED** (2026-08-08)  
**Milestone:** Find real screenshots by remembered text — offline, via FTS.

**Sprint 7 was NOT started during Sprint 6 implementation.**

---

## Acceptance

**Accepted by:** Product owner (physical-device verification)  
**Date:** 2026-08-08  

Physical-device verification **passed** on a real iPhone. Engineering DoD + owner device validation complete.

See also: `reviews/sprint-06-review.md`.

---

## Physical-device verification (PASSED)

Verified on real iPhone:

| Check | Result |
|-------|--------|
| Real OCR text search works correctly | Pass |
| Existing screenshots found via recognized text | Pass |
| Different text-search scenarios work as expected | Pass |
| Search returns real screenshot results | Pass |
| Sprint 6 production FTS Search functions on-device | Pass |

Owner confirmation (2026-08-08): production FTS Search is functioning correctly on-device.

---

## What shipped

### Production FTS Search
- Replaced full-library in-memory scoring in `GRDBMemoryRepository.search` with **FTS5 `MATCH`** on Sprint 5 `screenshot_fts`
- Single index only — no parallel search index
- Safe query builder: `SearchFTSQuery` (normalize → tokenize → quote/escape → `AND` + prefix)

### Results resolve to real screenshots
- Hits join existing `screenshot` rows
- UI continues to use `STScreenshotGridItem` / PhotoKit thumbs + existing fullscreen viewer
- No duplicate screenshot creation
- Membership / Collection metadata unchanged by Search

### Access / removal
- Filter: `access_state = 'available'` AND `is_removed_from_app = 0`
- Limited / inaccessible assets excluded from results

### OCR lifecycle
- Pending OCR → not in FTS → not found
- After `completeOCRSuccess` FTS upsert → immediately searchable (no restart / reimport)

### Ranking (lexical only — no AI)
1. `bm25(screenshot_fts)`  
2. `is_favorite`  
3. `created_at` / `id`  
Documented in `docs/22_SPRINT_6_SEARCH.md`

### UX (no product redesign of Search shell)
- Preserved Search layout, debounce, cancel-stale
- User-facing match caption (not OCR dumps on tiles)
- Suggestions: live Collection titles via `LocalSearchSuggestionsProvider` (fallback static chips)
- Acceptance polish (device session): keyboard dismiss, gallery density control, empty-state illustration — still within Search UX; no Collection/Needs Review mutations

### Scope guardrail
Search does **not** create/rename/assign Collections or move items out of Needs Review (except unchanged existing UI paths unrelated to Search intelligence).

---

## Automated tests

**21/21 passed** (`GRDBMemoryRepositoryTests`), including:
- FTS tokenize / escape
- FTS hit for OCR text; case / multi-word / punctuation
- Empty OCR + no-result + inaccessible + soft-remove
- Live OCR→search without restart
- Search does not mutate memberships

---

## Docs

- `docs/22_SPRINT_6_SEARCH.md` — CLOSED / ACCEPTED  
- `docs/13_IMPLEMENTATION_ROADMAP.md` — Sprint 6 status CLOSED / ACCEPTED  
- `docs/README.md` — index updated  

---

## Next

Sprint 6 closed. Sprint 7 plan: `docs/23_SPRINT_7_MANUAL_ORGANIZATION.md`.  
**Do not implement Sprint 7** until that plan is explicitly approved.
