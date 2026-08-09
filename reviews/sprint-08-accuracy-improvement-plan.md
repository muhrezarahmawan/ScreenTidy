# Sprint 8 — Accuracy Improvement Plan

**Status:** **APPROVED** (2026-08-09) — remediation in progress  
**Sprint 8 status:** **IMPLEMENTED BUT NOT ACCEPTED**  
**Product gate:** Materially useful automatic organization on real screenshots (Architecture **C**) — **P0 infrastructure alone is not sufficient**  
**Do not start Sprint 9.**  
**Do not lower `assignThreshold` / `createThreshold`.**

Related:
- Intelligence architecture (APPROVED): `reviews/intelligence-architecture-multisignal-proposal.md`
- Architecture lock: `docs/24_SPRINT_8_COLLECTION_RESOLVER.md`
- AI pipeline: `docs/07_AI_PIPELINE.md`
- Privacy: `docs/08_PRIVACY_SECURITY.md`
- Hosted gateway (P0): `docs/25_RAILWAY_GATEWAY.md`
- Gateway code: `gateway/README.md`
- Prior handoff: `reviews/sprint-08-completion-report.md`

---

## Approved decisions (2026-08-09)

| # | Decision | Locked choice |
|---|----------|---------------|
| 1 | Gateway | ScreenTidy-owned **stateless HTTPS** proxy; iOS never holds provider keys |
| 2 | Initial model | **GPT-5.6 Terra** via OpenAI Responses API (gateway-configured; replaceable) |
| 3 | Output | Strict structured schema; validate server + on-device |
| 4 | Image | Long edge **1024**, JPEG **~0.75**, tunable constants |
| 5 | Signals | OCR-normalized + image together when cloud permitted; image mandatory if OCR empty |
| 6 | Create | Keep 0.70 / 0.85 + **corroboration** required for new Collections |
| 7 | Batch ceiling | **8** (prefer smaller natural groups) |
| 8 | Cross-shot context | Required for human-like naming |
| 9 | Profiles | Compact local Collection context profiles |
| 10 | Naming | Context vs type/facet (**Vision nouns never name Collections**) |
| 11 | Confidence | Multi-signal local final; conflicts reduce confidence |
| 12 | Eval UI | DEBUG-only labels + aggregate metrics |
| 13 | Inspector | Full provenance for decisions |
| 14 | Reprocess | DEBUG Needs Review re-run by resolver version |
| 15 | Privacy | Explicit consent; document **real** retention (no unverified ZDR claims) |
| 16–18 | Cost / model eval | Cache, bounds, no launch thrash; Terra initial only |
| 19–20 | Acceptance | Measure before/after; Sprint 8 not closed on smoke alone |
| 21 | Intelligence | Architecture **C** phases P0→P6 inside Sprint 8 remediation |
| 22 | Hosting | Railway HTTPS (not Mac LAN) for physical-device path |

---

## Root cause (unchanged)

Primary bottleneck was `OnDeviceStructuredUnderstandingProvider` (OCR keyword stand-in) with no live multimodal gateway. Thresholds were not the bug. Product gap remains **isolated per-shot understanding** — Architecture C addresses clustering + local visual/semantic evidence after P0.

See prior plan sections for failure categories A–I.

---

## Remediation target pipeline

```
Screenshot
  → org-normalized OCR (Search raw untouched)
  → local profiles + optional batch cluster (≤8)
  → ScreenTidy gateway → GPT-5.6 Terra (structured)
  → on-device CollectionResolver (sole authority)
  → reuse | create (corroborated) | Needs Review
```

---

## STOP conditions for remediation completion

- Build + tests green  
- Gateway config + privacy notes  
- DEBUG evaluation workflow  
- Physical-device acceptance checklist  
- Measured results where available  
- **Sprint 8 still NOT ACCEPTED** until device review  
- **Sprint 9 not started**
