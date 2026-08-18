# MVP Compression — Implementation Report (Slice 0/1)

**Date:** 2026-08-11  
**Verdict:** Slice 1 vertical slice is **implemented in code**. Slice 0 hosted gateway is **not yet demonstrably reachable** from a physical iPhone in this environment (Railway login required).  
**Do not ACCEPT** the product slice until you complete physical testing.

---

## 1. Files changed

### Gateway
- `gateway/src/prompt.ts` — contextual batch question; sharedContext = related subset
- `gateway/src/schemas.ts` — `unresolvedIds`, `sharedContext.evidence`, optional member facets/source fields
- `gateway/src/handlers.ts` — pass optional local evidence into batch prompt
- `gateway/src/openaiClient.ts` — validate unresolvedIds / overlap with sharedContext

### iOS
- `ScreenTidy/Domain/Models/OrganizationModels.swift` — batch member payload; SharedBatchContext CodingKeys (`memberLocalIds` + evidence)
- `ScreenTidy/Data/Organization/EphemeralMultimodalUnderstandingProvider.swift` — `POST /v1/understand-batch` when batchMembers > 1; plumb sharedContext
- `ScreenTidy/Data/Organization/CompositeUnderstandingProvider.swift` — load JPEGs for batch peers
- `ScreenTidy/Data/Organization/OrganizationService.swift` — build batch payloads from local cluster; failure → Needs Review
- `ScreenTidy/Data/Persistence/GRDBOrganizationRepository.swift` — photosLocalIdentifier on cluster snapshots

### Tests / docs
- `ScreenTidyTests/MVPCompressionVerticalSliceTests.swift`
- `reviews/mvp-compression-plan.md` (APPROVED status)
- `reviews/mvp-slice-0-hosted-gateway.md`
- `reviews/mvp-compression-implementation-report.md` (this file)

---

## 2. Railway / hosted gateway status

| Item | Status |
|------|--------|
| Deploy `gateway/` to Railway | 🔵 Blocked — `railway` CLI not available / not logged in here |
| `OPENAI_API_KEY` on Railway only | Documented — set during your deploy |
| `GATEWAY_SHARED_SECRET` | Documented — generate + mirror into Secrets |
| HTTPS domain + `/health` | Pending your deploy |
| `Secrets.xcconfig` | Missing — copy from `.example` after deploy |
| Physical iPhone default HTTPS | Pending Secrets + rebuild |

Follow: `docs/25_RAILWAY_GATEWAY.md` + `reviews/mvp-slice-0-hosted-gateway.md`.

Until then DEBUG may still fall back to `http://127.0.0.1:8787` when no bundled HTTPS URL is configured.

---

## 3. Exact production batch path

```
OrganizationService.organizeIfNeeded
  → fetchPendingOrganizeMembers
  → OrganizationBatchPlanner.clusterDetailed (maxBatchSize=8)
  → build UnderstandingBatchMemberPayload[] (OCR, facets, source hints, PhotoKit IDs)
  → CompositeUnderstandingProvider (load JPEGs for members)
  → if batchMembers.count > 1:
        EphemeralMultimodalUnderstandingProvider → POST /v1/understand-batch
     else:
        POST /v1/understand
  → ScreenshotUnderstanding (+ sharedContext if seed ∈ related)
  → CollectionResolver.resolve
  → GRDBOrganizationRepository.applyResolverDecision
       → REUSE | CREATE | NEEDS REVIEW
```

Cloud never creates/reuses Collections directly.

---

## 4. Candidate batch construction

- Seed = screenshot being organized  
- Peers = pending organize members (limit 40)  
- Clusterer = existing MultiSignalClusterer / OrganizationBatchPlanner  
- Ceiling = `ResolverPolicy.maxBatchSize` (8)  
- Multimodal batch only when **>1** members after clustering  
- No change to local facet/platform heuristics (frozen)

---

## 5. Multimodal input schema (batch)

Per member (optional fields omitted when empty):

- `localId`
- `ocrNormalized`
- `createdAt`
- `imageBase64` / `imageMimeType` (bounded JPEG)
- `visualFacets` (optional)
- `sourcePlatform` / `contentType` / `contentFamily` (optional)

Plus request-level:

- `correlationId`, `schemaVersion`, `allowVisual`
- `eligibleCollections` (compact profiles)

---

## 6. Multimodal output schema (batch)

Evolved `/v1/understand-batch` (minimal):

```json
{
  "members": [ { "localId": "...", "...understanding fields..." } ],
  "sharedContext": {
    "title": "Trip to Abu Dhabi",
    "confidence": 0.91,
    "memberLocalIds": ["A","B","C"],
    "evidence": ["flight","hotel"]
  },
  "unresolvedIds": ["E"],
  "provider": "...",
  "promptVersion": "...",
  "schemaVersion": "..."
}
```

iOS attaches `sharedContext` to the seed understanding **only if** the seed ID is in `memberLocalIds`.  
Unresolved seeds clear sharedContext and add `unresolved_in_batch`.

---

## 7. Resolver wiring

- Thresholds **unchanged**: REUSE 0.70 / CREATE 0.85  
- Existing sharedContext corroboration in `CollectionResolver` retained  
- Final authority remains on-device resolver → GRDB

---

## 8. Failure → Needs Review behavior

| Failure | Behavior |
|---------|----------|
| Timeout / offline / 5xx / 429 / 408 | `pendingNetwork` (bounded retry via queue) |
| Malformed / invalid schema / 4xx (non-retry) | Apply **Needs Review** decision; `organize_status = ready` |
| Missing image (image-only) | Empty understanding → resolver NR path (existing) |
| Consent not determined / declined | Existing skip / on-device paths |

Ordinary cloud intelligence failures must **not** leave screenshots permanently in `organize_status = failed`.

---

## 9. Automated tests

`ScreenTidyTests/MVPCompressionVerticalSliceTests.swift`:

- SharedBatchContext decodes/encodes `memberLocalIds`
- Resolver thresholds remain locked with sharedContext present
- Malformed cloud failure → ready + unassigned (Needs Review), not `failed`
- Batch ceiling matches policy (5–8 / max 8)

---

## 10. Very simple physical iPhone test procedure

1. Complete Slice 0 (Railway + Secrets + rebuild). Confirm Resolver Inspector health = green HTTPS.  
2. Accept cloud understanding consent.  
3. Import / sync ~10–20 mixed screenshots (travel + chat + 1–2 distractors).  
4. Trigger organize (queue / app foreground).  
5. Check Home: related travel together?; distractors out or Needs Review?; existing Collection reused if present?  
6. Airplane mode → reorganize one item → must stay usable (pendingNetwork or Needs Review), not stuck Failed forever.  
7. Open Resolver Inspector on one batch item — confirm batch context + sharedContext notes when applicable.

Then expand to 30–50 for Slice 2 product judgment (A–H). **Do not declare ACCEPT until that physical eval.**

---

## Status board

| Slice | Status |
|-------|--------|
| 0 Hosted gateway | 🔵 You deploy (checklist ready) |
| 1 AI Organizer vertical slice | ✅ Code complete — pending your physical proof |
| 2 30–50 physical product eval | ⛔ Next after Slice 0 |
| 3+ Shipping / polish / TestFlight | ⛔ After eval + freeze intelligence |

**STOP** — no further intelligence expansion.
