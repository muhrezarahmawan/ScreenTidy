# Sprint 8.0 — Intelligence Foundation Health — Completion Report

**Status:** **CLOSED / ACCEPTED**  
**Accepted:** 2026-08-10 (physical iPhone verification)  
**Canonical phase plan:** `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md`  
**Sprint 8 overall:** remains **OPEN / NOT ACCEPTED** until later phases land  
**Next phase:** **8.1 — Visual Understanding** — later **CLOSED / ACCEPTED**; see `reviews/sprint-08-1-completion-report.md`  
**Sprint 9:** **NOT STARTED**

---

## Goal

Make OCR + Visual Analysis queues process reliably on a physical device so later intelligence phases have real persisted Vision evidence.

---

## Device acceptance (PASSED)

| Check | Result |
|-------|--------|
| One Kick starts continuous drain | Pass |
| Pending → 0 | Pass |
| Claimable pending → 0 | Pass |
| Processing returns to 0 | Pass |
| Completed increases | Pass |
| Failed = 0 after remediation | Pass |
| Failure summary empty | Pass |
| No stuck pending/processing | Pass |
| Force-quit + reopen preserves completed | Pass |
| Pending remains 0 after relaunch | Pass |

---

## What shipped (foundation health)

1. **Visual worker lifecycle** — strong `Task` retention (OCR parity); claim → processing → complete / failed / inaccessible; continuous kick-on-finish drain  
2. **Claimability diagnostics** — Pending vs Claimable; reasons (missing Photos id / removed / inaccessible)  
3. **Kick parity** — Visual Intelligence Kick; launch / Home refresh wake with OCR  
4. **Reprocess** — clears stale labels / facets / feature prints; per-item + all  
5. **PhotoKit reliability** — bounded timeout; timeout = **transient** `failed`; missing asset = **terminal** `inaccessible`  
6. **Split Vision stages** — classify then feature-print; classify success + FP failure = **completed** with labels kept (`feature_print_status=failed`)  
7. **Fine-grained error codes** + DEBUG failure summary / failed list  
8. **Persistence** — labels, feature prints, status survive relaunch; DEBUG inspection does not mutate Collections  

---

## Explicitly out of scope (deferred)

- Sprint **8.1+** quality evaluation / clustering / Lab / embeddings  
- Vision filter threshold product tuning (8.1)  
- Resolver threshold changes  
- Railway / multimodal architecture changes  
- Sprint 9  

---

## Follow-on

Sprint **8.1 — Visual Understanding** evaluates whether Apple Vision evidence is *useful* for real screenshots (labels, neighbors, image-only). Do **not** implement until the 8.1 plan is explicitly accepted.
