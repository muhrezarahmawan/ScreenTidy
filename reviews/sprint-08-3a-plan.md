# Sprint 8.3A — Multimodal Screenshot Understanding Lab — Plan

**Status:** 🔵 **IMPLEMENTED — awaiting physical Lab evaluation** (approved 2026-08-10)  
**Depends on:** Sprint **8.2A ACCEPTED**; Sprint **8.2B ACCEPTED** as local candidate-grouping baseline (`reviews/sprint-08-2b-completion-report.md`)  
**Canonical roadmap:** `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md`  
**Date:** 2026-08-10

**R2b remains CANCELLED.** Railway / embeddings / Sprint 9 remain blocked unless Lab explicitly needs a hosted endpoint (prefer existing gateway).  
**8.3B+ not started.** **Do not ACCEPT 8.3A until physical evaluation.**

---

## 1. Goal

Determine whether a **multimodal model looking at the real screenshot image** can understand what the screenshot represents **better than the local heuristic layer** — especially for visually semantic cases where OCR/chrome rules abstain or fail.

Answer:

> Does multimodal content understanding close the semantic gaps that local Level 1 / 2A / 2B cannot?

This is a **DEBUG Lab** only. Zero Collection mutation. Zero production auto-organize change.

---

## 2. Non-goals (locked)

| Forbidden in 8.3A |
|-------------------|
| Create / rename / assign Collections |
| Change resolver thresholds |
| Change production auto-organize |
| Automatic full-library multimodal runs |
| Embeddings (8.7) |
| Railway deploy (unless later Lab explicitly needs hosted endpoint — default: reuse existing gateway patterns) |
| Sprint 9 |
| Collection names in multimodal output |
| Treating “LinkedIn post” as permission to create a “LinkedIn” Collection |
| Same-person face recognition product |
| 8.3B contextual group reasoning (deferred) |

---

## 3. Product principle (locked)

**Content understanding ≠ Collection understanding.**

Knowing `platform=linkedin` / `contentType=social_post` is evidence only.

Eventual product flow remains:

```
screenshots
→ local evidence (8.0–8.2B)
→ candidate grouping (8.2B baseline)
→ multimodal content understanding (8.3A Lab)
→ multimodal contextual group reasoning (8.3B+)
→ compare existing Collection profiles
→ REUSE or CREATE
→ human-friendly Collection identity (resolver-gated)
```

Dynamic Collection Invariant unchanged.

---

## 4. Multimodal model boundary

| Concern | Boundary |
|---------|----------|
| **Authority** | Screenshot **image** is authoritative; local OCR/Vision/facets/source evidence are supporting context the model may **disagree with** |
| **Scope** | Single-screenshot **content** understanding (surface / platform / type / family / descriptors) |
| **Not in scope** | Multi-shot shared context, Collection title proposals, REUSE/CREATE |
| **Transport** | Prefer existing ScreenTidy-owned gateway pattern (`EphemeralMultimodalUnderstandingProvider` lineage): **no provider API keys on device**; consent-gated |
| **Model** | Vision-capable multimodal via gateway (exact vendor/model pinned at implementation approval; OpenAI Responses / equivalent with **strict JSON schema**) |
| **Invocation** | Manual DEBUG button only — never background library sweep |
| **Caching** | Optional DEBUG-only cache keyed by screenshot id + image/ocr/local-evidence fingerprint; must not feed production organize |
| **Abstention** | Model may return `unknown` with low confidence; prefer honest unknown over false platform |

Reuse existing consent (`CloudUnderstandingPreferences`) and gateway bearer isolation. Document actual retention/ZDR status of the account used — do not claim ZDR unless verified.

---

## 5. Proposed structured schema (audit before implement)

Bounded / versioned internal evidence + open descriptors. **No Collection name field.**

```json
{
  "schemaVersion": "8.3a-content-v1",
  "surface": {
    "type": "app_screen",
    "confidence": 0.95
  },
  "platform": {
    "id": "whatsapp",
    "confidence": 0.96
  },
  "contentType": {
    "id": "chat",
    "confidence": 0.98
  },
  "contentFamily": {
    "id": "messaging",
    "confidence": 0.98
  },
  "embedded": {
    "present": false,
    "hints": []
  },
  "openDescriptors": [
    "conversation",
    "message_bubbles",
    "quoted_reply"
  ],
  "evidenceNotes": [
    "WhatsApp-style conversation UI",
    "alternating message bubbles",
    "timestamps"
  ],
  "disagreesWithLocal": true,
  "localDisagreementNotes": [
    "Local platform/type unknown; image shows messaging chrome"
  ]
}
```

### Bounded vocabularies (v1 — extend only by version bump)

**surface.type:** `app_screen` | `lock_screen` | `notification_center` | `unknown`

**platform.id:** `whatsapp` | `imessage` | `messenger` | `instagram` | `linkedin` | `facebook` | `gmail` | `mail` | `maps` | `browser` | `unknown` (+ sparse additions only with schema bump)

**contentType.id:** `chat` | `social_post` | `email` | `video_call` | `gameplay` | `person_photo` | `identity_document` | `article` | `product_page` | `map` | `boarding_pass` | `flight_booking` | `hotel_booking` | `receipt` | `reservation` | `unknown`

**contentFamily.id:** `messaging` | `social_media` | `email` | `communication` | `entertainment` | `people` | `identity_document` | `reading` | `commerce` | `navigation` | `travel` | `unknown`

**embedded.hints[]:** `{ "platform"?: string, "contentType"?: string, "kind": "notification" | "widget" | "other", "confidence": number }`

**openDescriptors / evidenceNotes:** free-text, capped length/count (e.g. ≤12 descriptors, ≤8 notes, ≤80 chars each) — supporting evidence only, **not** taxonomy.

### Lock-screen + Gmail example (must pass)

```json
{
  "surface": { "type": "lock_screen", "confidence": 0.97 },
  "platform": { "id": "unknown", "confidence": 0.9 },
  "contentType": { "id": "unknown", "confidence": 0.85 },
  "contentFamily": { "id": "unknown", "confidence": 0.85 },
  "embedded": {
    "present": true,
    "hints": [
      { "platform": "gmail", "contentType": "email", "kind": "notification", "confidence": 0.92 }
    ]
  },
  "openDescriptors": ["lock_screen", "notification"],
  "evidenceNotes": ["Gmail notification on lock screen; not a Gmail app screen"]
}
```

Prompt must explicitly forbid labeling the whole screenshot as Gmail/email solely from an embedded notification.

---

## 6. Image + local-evidence input design

For **one** selected screenshot (DEBUG):

| Input | Role |
|-------|------|
| **JPEG/PNG of screenshot** (PhotoKit load via existing multimodal image loader/encoder) | **Authoritative** |
| OCR text (raw + normalized) | Supporting |
| Vision labels (filtered) | Supporting |
| Level 2A facets + facet evidence | Supporting |
| Local source/type/family + surface + embedded (R2a) | Supporting — model may disagree |
| createdAt / timezone if useful | Supporting |
| Eligible Collections | **Omit in 8.3A** (avoid naming bias) |

Payload sketch:

```json
{
  "task": "screenshot_content_understanding_8_3a",
  "schemaVersion": "8.3a-content-v1",
  "image": { "mime": "image/jpeg", "base64": "…" },
  "localEvidence": {
    "ocrText": "…",
    "visionLabels": [{ "id": "…", "confidence": 0.9 }],
    "facets": ["chat"],
    "facetEvidence": [],
    "platform": "unknown",
    "contentType": "unknown",
    "contentFamily": "unknown",
    "surface": "app_screen",
    "embeddedHints": [],
    "createdAt": "2026-08-10T…"
  },
  "instructions": {
    "imageIsAuthoritative": true,
    "mayDisagreeWithLocal": true,
    "noCollectionNames": true,
    "preferUnknownOverGuess": true,
    "separateSurfaceFromEmbedded": true
  }
}
```

---

## 7. DEBUG Lab UX (Visual Eval)

Add section: **MULTIMODAL UNDERSTANDING LAB**

- Button: **Analyze with Multimodal AI** (disabled without consent / unreachable gateway)
- Side-by-side:

**LOCAL UNDERSTANDING**  
platform / type / family / surface / embedded (+ confidences when present)

**MULTIMODAL UNDERSTANDING**  
same fields + openDescriptors + evidenceNotes + disagreement flag

- Manual judge (DEBUG only, local notes): **CORRECT** | **PARTIALLY CORRECT** | **WRONG** (+ optional free-text note)
- Show request cost/latency/correlation id if available
- Never write Collections; never enqueue organize

---

## 8. Privacy / cost strategy

| Rule | Detail |
|------|--------|
| Consent | Existing cloud-understanding disclosure; Lab blocked if declined |
| Keys | Provider keys only on gateway; device holds gateway bearer only |
| Ephemeral | Prefer no long-term cloud retention of images; document actual account ZDR/retention |
| Cost | Manual per-shot only; hard cap e.g. 1 request / tap; optional daily DEBUG cap |
| Size | Bound image long-edge / JPEG quality (reuse `MultimodalImageEncoder`) |
| Logging | No OCR/image bodies in analytics; DEBUG traces stay on-device |
| Production | Lab path must not be wired into `OrganizationService` auto path in 8.3A |

---

## 9. Physical test matrix (~15–25 shots)

| # | Class | Local expectation | Multimodal expectation |
|---|-------|-------------------|------------------------|
| 1 | WhatsApp chat (no “WhatsApp” OCR) | often unknown type/platform | whatsapp + chat + messaging |
| 2 | Instagram post | often weak/unknown | instagram + social_post + social_media |
| 3 | LinkedIn post | often weak/unknown | linkedin + social_post + social_media |
| 4 | Email app screen | may work locally | email + email; platform gmail/mail if evidenced |
| 5 | Lock screen + Gmail notification | surface lock; embedded gmail | same; **not** whole-shot Gmail |
| 6 | Notification Center | often abstain/weak | surface NC; embedded apps as hints |
| 7 | Boarding / flight | strong local facet | agree or refine |
| 8 | Hotel | strong local facet | agree or refine |
| 9 | Map | strong when OCR nav | map + navigation |
| 10 | Receipt | strong when OCR | receipt + commerce |
| 11 | Article / browser | often weak | article + reading; platform browser if clear |
| 12 | Identity document | multi-cue local | identity_document |
| 13 | Video call | local fail | video_call |
| 14 | Gameplay | local fail | gameplay |
| 15 | Portrait / person photo | local fail / deferred | person_photo (not person identity) |
| 16 | Product page | may work | product_page + commerce |
| 17 | Ambiguous app UI | abstain OK | unknown OK if honest |
| 18–25 | Extras / repeats for confidence | — | measure consistency |

Judge each: LOCAL vs MULTIMODAL × CORRECT / PARTIAL / WRONG.

**Success question:** Multimodal clearly wins on visually semantic gaps (1–3, 5–6, 13–15) without regressing lock-screen embedded safety or inventing Collection names.

---

## 10. Acceptance criteria (8.3A Lab)

Accept 8.3A **Lab** when:

1. Manual multimodal analysis runs on-device for selected shots with image attached.  
2. Strict schema validates; no Collection name field present.  
3. Side-by-side LOCAL vs MULTIMODAL DEBUG UI works; manual labels persist for the session/eval notes.  
4. Physical matrix (~15–25) completed.  
5. Multimodal **materially outperforms** local on visually semantic cases (WhatsApp-without-OCR, social posts, video call, gameplay, portrait-like, lock+embedded).  
6. Lock screen + Gmail does **not** become whole-shot Gmail/email.  
7. Zero Collection mutations; organize/resolver thresholds untouched.  
8. Privacy/consent path documented; keys not on device.

**Not required for 8.3A ACCEPT:** production integration, group reasoning, naming quality, embedding retrieval.

---

## 11. Files likely to change (when approved)

| Area | Likely files |
|------|----------------|
| Schema / DTO | New `ScreenshotContentUnderstanding` (or extend understanding models carefully without Collection fields) |
| Lab client | New thin Lab provider **or** dedicated gateway route e.g. `/v1/content-understand` (prefer separate from Collection-oriented `/v1/understand` to avoid eligible-collection bias) |
| Image | Reuse `PhotoKitMultimodalImageLoader`, `MultimodalImageEncoder` |
| DEBUG UI | `VisualIntelligenceDebugInspectorView.swift` (+ small view model/store for Lab results/labels) |
| Gateway (if in-repo) | Schema + prompt for content-only task |
| Tests | Schema decode/validate; lock-screen fixture; disagreement-with-local fixture; UI/DTO smoke |
| Docs | This plan + short completion notes after Lab |

Avoid wiring into `OrganizationService` production path.

---

## 12. Deferred to 8.3B / 8.4+

| Item | Owner |
|------|-------|
| Multi-image / candidate-group contextual reasoning | 8.3B+ |
| Collection title proposals / REUSE-before-CREATE Lab | 8.3B / 8.4 |
| Resolver integration / production organize path | 8.6 |
| Prompt/schema refinement for naming usefulness | 8.4 |
| Benchmark v1 (30–50 scored) | 8.5 |
| Embeddings | 8.7 if needed |
| Same-person identity | dedicated later sprint |
| Anti–double-count scoring in local clusterer | only if false merges proven; not 8.3A |

---

## 13. Risks

| Risk | Mitigation |
|------|------------|
| Model invents Collection-like titles | Schema forbids; prompt forbids; validate absence |
| Whole-shot Gmail from lock notification | Explicit surface/embedded split + fixture |
| Cost / accidental library sweep | Manual button only; caps |
| Gateway LAN flakiness | Lab clearly reports unreachable; no fake success |
| Local evidence biases model | Prompt: image authoritative; allow disagreement |
| Scope creep into 8.3B | Single-shot content only in 8.3A |
| Privacy perception | Consent + no keys on device + retention honesty |

---

## 14. Decision asked

**STOP for approval.**

Please reply with one or both:

1. `ACCEPT 8.2B AS LOCAL BASELINE` (optional: edit limitations)  
2. `APPROVE Sprint 8.3A plan` / `REVISE 8.3A …`

**Do not implement R2b.**  
**Do not implement 8.3A until approved.**
