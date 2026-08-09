# Sprint 6 — Search (FTS Wired)

**Status:** **CLOSED / ACCEPTED** (2026-08-08)  
**Depends on:** Sprint 3 + 4 + 5 — all **CLOSED / ACCEPTED**  
**Canonical roadmap:** `docs/13_IMPLEMENTATION_ROADMAP.md` § Sprint 6  
**UX shell (preserve):** `docs/02_UX_SPEC.md` § Search  

**Milestone:** “Find real screenshots by remembered text — offline, via FTS.”

**Approved:** 2026-08-08 (owner requirements incorporated).  
**Accepted:** 2026-08-08 (physical-device verification **PASSED**).  
**Completion report:** `reviews/sprint-06-completion-report.md`.
**Review:** `reviews/sprint-06-review.md`.

---

## Scope boundary (locked)

| In scope | Out of scope |
|----------|----------------|
| Production offline Search over Sprint 5 OCR → FTS | Screenshot classification |
| Lexical FTS5 only (no semantic/AI/vector) | Collection creation from intelligence |
| Real PhotoKit thumbs + existing viewer | Automatic Collection assignment |
| Access-state + soft-remove filtering | Movement out of Needs Review |
| Deterministic lexical ranking | Sprint 7 / Sprint 8 implementation |

**Roadmap reminder:** Sprint 7 = manual assignment. Sprint 8 = AI filing / Collection Resolver.

---

## Acceptance requirements (approved)

### 1. Production FTS path
- Remove/replace temporary in-memory/mock ranking for **production** Search (`GRDBMemoryRepository.search`).
- Results come from `screenshot_fts` populated by Sprint 5 OCR.
- **Do not** create a second parallel search index.

### 2. Real screenshots
- Resolve to existing screenshot records + PhotoKit assets.
- Display existing real thumbnails; open existing fullscreen viewer.
- Preserve Collection/membership metadata; never duplicate screenshot rows.

### 3. Access state
- Exclude `access_state != available` and `is_removed_from_app = 1`.
- Respect Limited Photos; Search reflects currently accessible set (Sprint 4 rules).

### 4. OCR lifecycle
- New rows may exist before OCR completes (not yet searchable via FTS).
- After OCR completes + FTS upsert, screenshot is searchable **without** reinstall, DB reset, re-import, or app restart.

### 5. Query behavior
Verify at minimum: single word, multiple words, case differences, punctuation, text in different screenshot regions, no-result query, empty OCR screenshots.

**FTS query normalization / escaping (canonical):**
1. Trim whitespace.
2. Apply `OCRPipeline.normalizedForSearch` (lowercase + collapse whitespace) for consistency with indexed text.
3. Tokenize to Unicode letters/numbers only (punctuation discarded).
4. Cap at 12 tokens.
5. If no tokens → empty `SearchResponse` (not an error).
6. Build FTS5 expression: each token double-quoted (internal `"` doubled), joined with `AND`.
7. Tokens length ≥ 2 use prefix form `"token"*`; length-1 use exact `"t"`.
8. Never pass raw user input to `MATCH`. Malformed input cannot crash Search.

Sprint 6 remains **lexical offline FTS** — no semantic/AI/vector search.

### 6. Performance
- Query GRDB/FTS; do **not** load all screenshots to score in memory.
- No PhotoKit requests for off-screen results (LazyVGrid + existing thumbnail provider).
- Preserve thumbnail caching; debounce typing; cancel obsolete searches (existing ViewModel).
- DB work on GRDB reader pool (off main actor await).

### 7. Result ordering (deterministic lexical)
Documented ranking (no AI relevance):
1. Primary: FTS `bm25(screenshot_fts)` (better FTS match first).
2. Tie-break: `is_favorite` DESC.
3. Tie-break: `created_at` DESC, then `id` DESC.

`SearchHit.relevanceScore` = `-bm25 + favoriteBoost + tinyRecencyNudge` for stable Swift-side display only.  
`matchedSignals` includes `.ocr` for FTS hits; `.collection` when Collection title also matched.  
**Sprint 8 intelligence must not be mixed into this ranking.**

### 8. Empty / error states
Preserve approved Search UX. Handle: empty query, no matches, empty OCR, DB failure, inaccessible assets, thumbnail failure. **No OCR/debug chrome on production tiles.**

### 9. Privacy
Fully local. No network search. No shipping OCR text, queries, thumbs, or bytes off-device as part of Sprint 6.

### 10. Regression
No redesign of Home, Collections, Viewer, Cleanup, Settings, onboarding, tab bar, or Search layout. Preserve Sprint 2–5 accepted behavior.

### 11. Device acceptance
Physical-device verification **PASSED** (2026-08-08). See completion report.

### 12. Scope guardrail
Search must **never** create/rename/infer Collections, assign membership, or remove screenshots from Needs Review.

---

## Architecture

```
SearchViewModel (debounce + cancel)
  → SearchProviding.search(query)
  → GRDBMemoryRepository FTS MATCH on screenshot_fts
  → JOIN screenshot (available, not removed)
  → ORDER BY bm25, favorite, created_at
  → SearchResponse { collections (title match), hits }
```

OCR consumption: Sprint 5 `completeOCRSuccess` → FTS upsert; Search only reads FTS.

Suggestions: Collection title shortcuts from live DB (not OCR dumps); fallback chips if none.

---

## Definition of Done

1. Production Search uses FTS; in-memory full-library scoring removed from GRDB path ✅  
2. Single FTS index (`screenshot_fts`) — no parallel index ✅  
3. Results are real screenshots + PhotoKit thumbs + existing viewer ✅  
4. Inaccessible / removed excluded ✅  
5. Post-OCR FTS upsert → immediately searchable without restart ✅  
6. Query normalization/escaping documented + safe ✅  
7. Lexical ranking documented; no AI scoring ✅  
8. Empty/error UX preserved; no OCR on tiles ✅  
9. Privacy local-only ✅  
10. No Collection / Needs Review mutations from Search ✅  
11. Automated tests green ✅  
12. Completion report + device checklist ✅  
13. Physical-device verification **PASSED** ✅  
14. **Sprint 7 not started during Sprint 6** ✅  

**Status:** **CLOSED / ACCEPTED** (2026-08-08).

---

## Non-goals

Classification · auto Collections · Needs Review filing · embeddings · Sprint 7/8 implementation during Sprint 6
