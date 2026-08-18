# Sprint 8 Phased Code Audit

**Date:** 2026-08-10 (updated after Dynamic Collection Invariant lock)  
**Canonical phases:** `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md`  
**Dynamic Collection Invariant (LOCKED):** no predefined Collection taxonomy — see `docs/26_…`  
**Sprint 8 overall:** OPEN / NOT ACCEPTED · **Sprint 9:** NOT STARTED  
**Active phase:** **8.1** (Visual Understanding) — DEBUG tooling shipped; awaiting physical-device quality evaluation  
**8.0 completion:** `reviews/sprint-08-0-completion-report.md`

---

## Phase status summary

| Phase | Classification | Notes |
|-------|----------------|-------|
| **8.0** | **CLOSED / ACCEPTED** | Physical iPhone: drain works; Pending/Failed=0; completed persists across relaunch. |
| **8.1** | **IN PROGRESS** | DEBUG raw/filtered/neighbors/resolution tooling shipped; physical quality eval pending ACCEPT. |
| **8.2** | **PARTIAL** | `MultiSignalClusterer` wired; quality gated on useful Vision evidence (8.1). |
| **8.3** | **NOT STARTED** | No DEBUG multi-image Lab; gateway batch unused from iOS Lab. |
| **8.4** | **PARTIAL** | Gateway prompt/schema exist; no Lab feedback loop. |
| **8.5** | **NOT STARTED** | Benchmark must judge naming usefulness/equivalence — **not** exact match to illustrative Collection titles; no taxonomy seed list. |
| **8.6** | **PARTIAL** | Production org + resolver 0.70/0.85 exist; per-shot multimodal, not proven cluster Lab. |
| **8.7** | **NOT STARTED / DEFER** | No embeddings code; correctly deferred. |
| **8.8** | **PARTIAL** | Concurrency caps / version skip / fingerprint cache only. |

---

## Reuse vs premature

| Area | Verdict |
|------|---------|
| OCR queue / PhotoKit loaders | **Reuse** |
| VisualAnalysis* / v9 migration / failure remediation | **Reuse** — do not rebuild for 8.1 |
| MultiSignalClusterer | **Reuse** for 8.2 (after 8.1 quality judgment) |
| CollectionResolver + thresholds | **Reuse** — do not lower bars |
| Gateway `/v1/understand*` | **Reuse later** for 8.3 Lab — Railway paused |
| Embeddings | **Premature** if started now |
| Full production cluster multimodal | **Premature** before 8.3–8.5 |

---

## Sprint 8.0 — CLOSED (summary)

**Root cause (lifecycle):** Visual worker used `Task.detached` + weak capture; claims did not advance (`Pending≫0`, `Processing=0`).

**Remediation landed:** strong Task; claimability diagnostics; Kick parity; reprocess clears outputs; PhotoKit timeout → transient failed; missing asset → inaccessible; split classify/FP with partial success; fine-grained errors + DEBUG failure UI.

**Device:** Accepted 2026-08-10 — see completion report.

---

## Sprint 8.1 — Visual Understanding *(NEXT — plan only)*

### Already available for quality evaluation
- Persisted filtered labels + confidence, facets, feature-print status/blob
- DEBUG **Settings → Developer → Visual Intelligence** (≤20 recent, detail: OCR preview, labels, FP, neighbors by ID+distance, candidate cluster)
- On-device noun denylist + resolver create gates (Vision nouns ≠ Collection titles)
- `MultiSignalClusterer` signal scores (DEBUG cluster cohesion; breakdown not shown in UI)

### Gaps that block quality judgment (minimal DEBUG)
- Neighbor / cluster member **thumbnails**
- Neighbors scoped only to recent ≤20 window
- No raw vs filtered label comparison
- No DEBUG filter knobs / per-shot quality notes
- No lightweight export of 10–20 evaluation rows
- Declared visual long-edge 1024 vs actual PhotoKit load at OCR 1800 (document / decide in 8.1)

### Stop rule
Do **not** implement 8.1 until the focused plan is explicitly accepted. Do **not** start 8.2+.
