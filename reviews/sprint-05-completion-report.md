# SPRINT 5 COMPLETION REPORT

**Sprint:** 05 — On-Device Screenshot Understanding Foundation (OCR)  
**Date:** 2026-08-08  
**Status:** **CLOSED / ACCEPTED** (2026-08-08)  
**Milestone:** Screenshots are locally understandable.  
**Explicitly not:** Automatic Collections / production Search / cloud AI.

**Sprint 6 was NOT started during Sprint 5.**

---

## Acceptance

**Accepted by:** Product owner (physical-device verification)  
**Date:** 2026-08-08  

Physical-device verification **passed** on a real iPhone. Engineering DoD + owner device validation complete.

See also: `reviews/sprint-05-review.md`.

---

## What shipped

### Migration / schema
- GRDB migration `v3_ocr`
- Columns: `ocr_status`, `ocr_version`, `ocr_language`, `ocr_attempt_count`, `ocr_claimed_at`, `ocr_last_attempt_at`, `ocr_next_retry_at`, `ocr_last_error`
- Existing `ocr_text` retained as **raw** extracted text
- Indexes for claim / retry / stale recovery
- Photos upserts start as `ocr_status = pending`

### OCR state machine
`pending` → `processing` → `completed`  
`processing` → `failed` → backoff → `pending`  
`pending`/`processing` → `inaccessible` when Photos access shrinks (completed OCR preserved)  
`inaccessible` → `pending` when access returns (if incomplete / version-stale)

Empty OCR (`completed` + `ocr_text = ""`) is a **valid success** (no retry).

### OCR pipeline version
- `OCRPipeline.currentVersion = **1**`
- Completeness requires `completed` **and** matching version
- Stale versions requeue without destructive DB reset

### Queue / retry
- Max concurrency **2** (fixed; not scaled to library size)
- Newest-first claim order
- Crash-safe: stale `processing` claims recovered on kick/launch (`ocr_claimed_at`)
- Exponential backoff; max 8 attempts
- Downscaled PhotoKit images (long-edge ~1800); resources released per job

### FTS population
- On OCR success: upsert `screenshot_fts.ocr_text` from **normalized** form of raw text
- Raw text remains on `screenshot.ocr_text`
- **Search UX/ranking unchanged** (Sprint 6)

### Privacy
- Vision on-device only
- No external OCR/LLM APIs
- Logs never include OCR body text

### Collections
- OCR completion does **not** create/rename/move/remove/file Collections or Needs Review

### DEBUG
- Settings → Developer → **OCR Inspector** (DEBUG only)
- Pipeline health counts + version
- Recent rows: thumbnails, OCR preview, status, version
- Detail: large screenshot, full selectable `ocr_text`, outcomes, Reprocess one / Reprocess all

---

## Automated tests

**17/17 passed** (`ScreenTidyTests`) at engineering handoff.

Coverage includes:
- Empty OCR → completed + FTS row
- Stale processing claim recovery
- Newest-first claim
- OCR does not change memberships / Needs Review count
- Prior fixture / photos / inaccessible tests retained

---

## Performance strategy

- Bound concurrency = 2  
- Newest-first drain  
- Downscaled Vision input  
- Non-blocking background Tasks  
- Large libraries drain across sessions  

---

## Known limitations (accepted / deferred)

- iCloud remote-only assets may fail transiently (`image_unavailable`) then retry  
- Optional `BGProcessingTask` not required/shipped for DoD  
- Search tab still uses temporary in-process ranking (Sprint 6 wires FTS)  
- Language field may be nil (Vision language not always surfaced)  

---

## Physical-device verification (PASSED — 2026-08-08)

Verified on real iPhone:

| Check | Result |
|-------|--------|
| OCR pipeline completes successfully | **Pass** |
| Real screenshots are processed | **Pass** |
| Text-heavy screenshots extract meaningful OCR text | **Pass** |
| Small text detected where possible | **Pass** |
| Screenshots without meaningful text → “No text detected” / empty completed | **Pass** |
| OCR results persisted and visible in DEBUG OCR Inspector | **Pass** |
| OCR processing does not modify Collections | **Pass** |
| No blocking OCR failures during device testing | **Pass** |

DEBUG: Settings → OCR Inspector used for visual OCR verification (thumbnail → detail → full text → optional reprocess).

---

## Docs

- `docs/21_SPRINT_5_OCR.md` — **CLOSED / ACCEPTED**  
- `docs/13_IMPLEMENTATION_ROADMAP.md` — Sprint 5 status closed  
- `reviews/sprint-05-review.md` — acceptance record  

---

## Next

Sprint 5 is closed.  
**Sprint 6 implementation must not start** until the Sprint 6 plan is explicitly approved.  
Canonical plan draft: `docs/22_SPRINT_6_SEARCH.md`.
