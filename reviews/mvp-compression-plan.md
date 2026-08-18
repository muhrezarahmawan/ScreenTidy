# ScreenTidy — MVP Compression Plan (AI Organizer Vertical Slice)

**Status:** ✅ **APPROVED** — Slice 1 implemented in code; Slice 0 deploy blocked on Railway login; Slice 2 physical eval pending you  
**Date:** 2026-08-11 (updated)  
**Product goal:** Automatically organize messy screenshots into useful dynamic Context Collections.  
**Not the goal:** Perfect intermediate screenshot classification.

---

## Strategy lock

Freeze local intelligence at current Level 1 / 2A / 2B baseline (Sprint 8.2B ACCEPTED).  
Stop treating Sprint 8.3A single-shot content Lab as a ship blocker.  
Prioritize: **hosted gateway + multimodal contextual batch → local resolver → ship UI**.

---

## Inventory (audit)

| Piece | Status | Reuse |
|-------|--------|-------|
| PhotoKit / OCR / Vision / FP / facets / source evidence | EXISTS | Freeze |
| MultiSignalClusterer + OrganizationBatchPlanner | EXISTS | Candidate batch builder |
| CollectionResolver (REUSE/CREATE/NR) | EXISTS | Sole authority — thresholds unchanged |
| Eligible Collection profiles → gateway | EXISTS | Keep |
| Gateway `/v1/understand` + `/v1/understand-batch` + `sharedContext` | EXISTS | Evolved (groups via sharedContext + unresolvedIds) |
| iOS production → `/v1/understand-batch` | **WIRED** | When local candidates > 1 |
| iOS plumbs `sharedContext` into resolver | **FIXED** | Decode `memberLocalIds`; attach when seed in group |
| Sprint 8.3A `/v1/content-understand` Lab | EXISTS | DEBUG only — not blocker |
| Hosted Railway + Secrets.xcconfig | **CHECKLIST** | See `reviews/mvp-slice-0-hosted-gateway.md` |
| Failed understand → Needs Review | **HARDENED** | Malformed → NR; pendingNetwork keeps retry |
| Shipping UI (Home/Search/Settings/manual/NR) | MOSTLY EXISTS | After physical eval |
| Sprint 9 Cleanup DoD | NOT ACCEPTED | After vertical slice |

---

## Deferred / skip

- Further local chrome heuristics (WhatsApp/IG/LinkedIn/NC/video/game/portrait)
- Reopening Sprint 8.2 / R2b
- Perfect platform/type/family as gate
- Embeddings, same-person, universal taxonomy
- Making 8.3A Lab ACCEPT a prerequisite for organize

---

## Minimum vertical slice

```
New screenshots
→ local OCR/signals (frozen)
→ MultiSignalClusterer candidate batch (~5–8, ceiling 8 today)
→ POST /v1/understand-batch (hosted HTTPS)
→ contextual sharedContext + unresolvedIds
→ CollectionResolver (REUSE / CREATE / NR)
→ GRDB
```

On ordinary cloud failure: Needs Review (usable) — not permanent `organize_status=failed`.  
Retryable network: `pendingNetwork` (existing queue backoff).

---

## Acceptance bar (product)

A–H as in product brief: group related, separate unrelated, reuse, create useful names, NR on uncertainty, manual correct, failure-safe, no fixed taxonomy.

Eval: 30–50 physical screenshots judging **final organization**, not intermediate labels.

**Do not declare Slice 1 accepted until physical product eval.**

---

## Implementation sequence

1. Deploy Railway gateway + Secrets — **you** (Slice 0 checklist)  
2. Wire iOS organize to `/v1/understand-batch` + sharedContext — **done in code**  
3. Harden failure → NR / retry — **done in code**  
4. Physical 30–50 eval on product outcomes — **next (you)**  
5. Freeze intelligence → Sprint 9 Cleanup → polish → TestFlight  

---

## Guardrails (locked)

1. Freeze local intelligence  
2. Batch ≤ 8  
3. Do not change CollectionResolver thresholds (0.70 / 0.85)  
4. Cloud never mutates Collections  
5. Failure fallback mandatory  
