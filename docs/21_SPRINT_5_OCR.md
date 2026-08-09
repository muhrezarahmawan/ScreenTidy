# Sprint 5 — On-Device Screenshot Understanding Foundation (OCR)

**Status:** **CLOSED / ACCEPTED** (2026-08-08)  
**Depends on:** Sprint 4 **CLOSED / ACCEPTED**  
**Milestone:** “Screenshots are locally understandable.”  
**Not:** “ScreenTidy organizes Collections automatically.”  
**Not:** Sprint 6 production Search.  
**OCR pipeline version:** `OCRPipeline.currentVersion = 1`

**Physical-device verification:** **PASSED** (2026-08-08). Recorded in `reviews/sprint-05-review.md` and `reviews/sprint-05-completion-report.md`.

---

## Goal

Turn real screenshots into structured, machine-understandable **local** data so Sprint 6 production Search (and later classification) can become real.

Pipeline boundary (locked):

```
SPRINT 5:  Photos → Vision OCR → GRDB raw text → FTS substrate   ✅ CLOSED
SPRINT 6:  FTS querying / ranking → production Search            (plan only until approved)
LATER:     Understanding → clustering → automatic Collections
```

---

## Non-goals (locked)

- Automatic Collection create / rename / move / Needs Review filing  
- Production AI / cloud / embeddings / clustering  
- Production duplicate detection / PhotoKit deletion  
- Replacing Search UX/ranking with FTS in this sprint  
- OCR chrome on production gallery / viewer  
- Unbounded concurrency scaled to library size  

---

## Approved guardrails

### 1. OCR must be versioned

Persist `ocr_version` (pipeline/config version — **not** app version).

A screenshot is OCR-complete only when:

`ocr_status == completed` **and** `ocr_version == OCRPipeline.currentVersion`

Changing recognition settings / preprocessing / normalization later re-queues rows whose version is stale — **no destructive DB reset**.

### 2. Explicit OCR state machine

Dedicated `ocr_status` (not nullable-text inference):

| State | Meaning |
|-------|---------|
| `pending` | Needs OCR (new, stale version, or restored access) |
| `processing` | Claimed by queue |
| `completed` | Success (including empty text) |
| `failed` | Processing error; may retry |
| `inaccessible` | Asset not available under current Photos access |

Flow:

```
new PhotoKit screenshot → pending → processing → completed

processing → failed → (backoff) → pending/processing

pending|processing → inaccessible (Limited/revoked)
inaccessible → pending (when access returns, if still incomplete / version stale)
```

Failed OCR **never** blocks browsing.

### 3. Empty OCR is valid success

`completed` + `ocr_text = ""` is valid (“no text detected”).  
Do **not** retry solely because Vision returned no text.  
Differentiate from `failed` (processing error).

### 4. Raw OCR vs Search normalization

- Domain/DB stores extracted OCR text on the screenshot row.  
- FTS holds a searchable representation derived from that text.  
- FTS is **not** the only store of OCR.  
- Sprint 6 may evolve normalization/ranking independently.

### 5. FTS is infrastructure only

Populate `screenshot_fts.ocr_text`.  
**Do not** replace current Search UX/ranking in Sprint 5.

### 6. Downscaled images only

OCR uses appropriately downscaled PhotoKit images (long-edge budget).  
Never load hundreds of full-resolution assets.  
Process jobs independently; release image resources after each job.

### 7. Bounded concurrency

Max concurrency = **2**.  
Do **not** scale with library size.  
Newest-first priority. Continuous controlled drain.

### 8. Crash-safe claims

If app dies while `processing`, launch recovery returns stale claims to `pending`/`failed` retry using persisted timestamps.  
Kill/relaunch during OCR is an acceptance test.

### 9. Photo accessibility is authoritative

Respect Sprint 4 `access_state`.  
Never OCR `inaccessible` assets.  
Do not destroy existing OCR when temporarily inaccessible.  
On restore: keep valid completed+current-version OCR; otherwise return to `pending`.

### 10. OCR never changes Collections

No create/rename/move/remove from Needs Review / categorize / membership / user-facing confidence.

### 11. Privacy

On-device Vision only. No external OCR/LLM APIs. No analytics or production logs containing OCR text or screenshot contents.

### 12. DEBUG inspector

DEBUG-only: state, text, version, attempts, last attempt, failure reason (safe), access state; Reprocess one / Reprocess all. Not in production UI. Visual verification: thumbnails + detail with full selectable OCR text.

---

## Vision APIs

| API | Role |
|-----|------|
| `VNRecognizeTextRequest` | Primary OCR |
| `VNImageRequestHandler` | Run against CGImage |
| PhotoKit image request | Downscaled load (network OK for iCloud) |

Defaults: `.accurate`, language correction on, confidence floor ~0.3, long-edge ~1600–2048.

`OCRPipeline.currentVersion` bumps when pipeline config changes.

---

## Architecture

```
Photos sync
  → upsert (source=photos)
  → ocr_status=pending (if new / version stale)
  → OCRQueue.kick()

OCRQueue (actor, max 2)
  → recoverStaleProcessingClaims()
  → claim next (newest first; available only)
  → load downscaled CGImage
  → VisionOCR.recognize
  → persist raw ocr_text + ocr_version + completed|failed
  → upsert screenshot_fts from raw text (normalization hook)
  → release image; next job
```

Protocols: `OCRProviding`, `OCRScheduling`, repository claim/complete/FTS APIs.

---

## Schema (`v3_ocr`)

| Column | Purpose |
|--------|---------|
| `ocr_status` | pending / processing / completed / failed / inaccessible |
| `ocr_version` | Pipeline version (Int) |
| `ocr_language` | Optional |
| `ocr_attempt_count` | Retries |
| `ocr_claimed_at` | Crash-safe claim timestamp |
| `ocr_last_attempt_at` | Last try |
| `ocr_next_retry_at` | Backoff |
| `ocr_last_error` | Safe error code/message (no OCR body) |
| Keep `ocr_text` | Raw extracted text |

Indexes: `(ocr_status, created_at DESC)`, `(ocr_status, ocr_next_retry_at)`, `(ocr_status, ocr_claimed_at)`.

New photos upserts → `ocr_status=pending`, `ocr_version=0` (or null until complete).  
`analysis_status` remains for later organize pipeline; OCR uses `ocr_status`.

---

## Physical-device acceptance checklist (PASSED — 2026-08-08)

| ID | Case | Result |
|----|------|--------|
| A | Text-heavy screenshot → meaningful text | **Pass** |
| B | Small text → reasonable OCR without full-res | **Pass** |
| C | Almost no text → completed + empty/minimal | **Pass** |
| D–J | Pipeline health / Collections untouched / inspector (as exercised) | **Pass** (owner device session) |

Owner confirmation: pipeline completes; real screenshots processed; meaningful OCR on text-heavy shots; small text where possible; “No text detected” for empty successes; results persisted in DEBUG inspector; **zero** Collection mutations; no blocking OCR failures.

---

## Definition of Done

1. Versioned OCR pipeline; stale versions requeue without DB wipe ✅  
2. Explicit `ocr_status` state machine including crash recovery ✅  
3. Empty text = completed success ✅  
4. Raw OCR on screenshot row; FTS populated as substrate only ✅  
5. Search UX unchanged (Sprint 6) ✅  
6. Downscaled images; concurrency = 2; newest first ✅  
7. Inaccessible respected; OCR preserved when possible ✅  
8. Zero Collection mutations from OCR ✅  
9. On-device privacy boundary held ✅  
10. DEBUG inspector + reprocess ✅  
11. Automated tests + build green ✅  
12. Completion report + owner device checklist ✅  
13. **Sprint 6 not started during Sprint 5** ✅  

---

## STOP

Sprint 5 is **CLOSED / ACCEPTED**.  
Sprint 6 plan: `docs/22_SPRINT_6_SEARCH.md`. Implementation only after explicit plan approval.
