# Sprint 8.2 — Multi-Signal Content Typing + Context Candidate Grouping — Plan

**Status:** **8.2A CLOSED / ACCEPTED** · **8.2B 📋 PLAN REVISION** (`reviews/sprint-08-2b-plan.md`)  
**Working mode:** 8.2A done → **STOP for revised 8.2B plan APPROVAL** → then implement 8.2B only  
**8.2B:** 📋 PLAN REVISION — awaiting APPROVAL — see `reviews/sprint-08-2b-plan.md`  
**Depends on:** Sprint **8.1 CLOSED / ACCEPTED** (`reviews/sprint-08-1-completion-report.md`)  
**8.2A completion:** `reviews/sprint-08-2a-completion-report.md`  
**Canonical roadmap:** `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md`  
**Why now:** Sprint 8.1 showed Vision often returns generic Level 1 labels (`document`, `adult`, …). ScreenTidy needs **Level 2A multi-signal structured content typing** locally — not forcing `VNClassifyImageRequest` to emit chat/flight/article. Visually semantic types defer to **8.3A multimodal**.

**Out of scope (locked):** Lab (8.3), multimodal naming, embeddings (8.7), Railway, resolver threshold changes, Collection taxonomy / dynamic naming implementation, reopening 8.1, Sprint 9; expanding deriver for notification_center / video_call / portrait / gameplay

---

## Dynamic Collection Invariant (LOCKED)

Internal content facets are a **bounded evidence vocabulary**. They must **never** auto-create Collections named Chats / Flights / Articles / Receipts / Maps / etc.

Collection identity remains open-ended and downstream (8.3+ multimodal + resolver).

---

## Goals (two questions)

| Sub-phase | Question | Output |
|-----------|----------|--------|
| **8.2A** | What kind of content is this screenshot? | Scored internal facets (+ confidence / provenance) |
| **8.2B** | Which screenshots likely belong together? | Candidate groups + cohesion — **no names, no Collections** |

Do **not** implement 8.2A and 8.2B in one blind pass.

---

## Semantic stack (do not collapse)

```
LEVEL 1   What is visible?          → Vision + FP          (8.1 CLOSED)
LEVEL 2A  What kind of content?     → multi-signal facets  (THIS FIRST)
LEVEL 2B  Which belong together?    → candidate grouping   (AFTER 8.2A ACCEPT)
LEVEL 3   Shared real-world context → multimodal           (8.3+)
LEVEL 4   Reuse / create Collection → local resolver       (thresholds unchanged)
```

---

## Sub-phase 8.2A — Multi-Signal Content Typing

### 8.2A goal

Refine beyond generic Level 1 `document` by combining **local** signals into internal facets with confidence. Prefer **unknown / weak / abstain** over confidently wrong types.

### Allowed facet vocabulary (evidence only)

`chat`, `social_post`, `article`, `flight_booking`, `boarding_pass`, `hotel_booking`, `receipt`, `map`, `product_page`, `reservation`, `ticket`, `design_reference`, `image_only`, `interior_reference`, `travel_imagery`, `unknown`

(Existing deriver names remain; add `flight_booking` / `ticket` / `article` / `unknown` only where scoring justifies.)

---

### Audit vs current code (8.2A)

#### Current architecture (reuse — no parallel classifier)

| Piece | Role today | 8.2A action |
|-------|------------|-------------|
| `ScreenshotFacetDeriver.derive(ocr, labels) → [String]` | Binary OCR substring (mostly) + light Vision | **Primary extension point** — scored multi-signal |
| `completeVisualSuccess` | Re-derives facets with OCR + filtered labels → `visual_facets_json` | Keep write path; may persist richer JSON later |
| `VisionVisualAnalysisService.analyze` | Calls deriver with `ocrText: nil` | Interim; persistence remains source of truth |
| Filtered Vision labels | Level 1 evidence in deriver | **Weak support only** — never sole type mapper |
| `OrganizationOCRNormalizer` | Org OCR normalize | Reuse for structure / entity helpers |
| On-device entity seeds | Soft city/hotel/topic in understanding | Optional cue source — not Collection titles |
| Visual Eval DEBUG | Shows facet string list | Show strength / provenance after 8.2A |
| `MultiSignalClusterer` | Consumes facet strings | **Do not redesign in 8.2A** (defer to 8.2B) |
| Resolver / Collection titles | Noun denylist | Unchanged; facets still ≠ titles |

#### Existing facet rules (today = single-keyword / OR-list gates)

| Facet | Current trigger | Risk |
|-------|-----------------|------|
| `boarding_pass` | Any of boarding/gate/seat/pnr/**flight** OR (arrow+airport + fixed IATA list) | Broad “flight” true; fixed IATA list incomplete |
| `hotel_booking` | **check-in** / hotel / reservation / guest / brand names | **False + on airline check-in** (device Case B) |
| `map` | maps/directions/… OR Vision `map` | Often OK; Vision alone weak |
| `receipt` | Any of total/subtotal/tax/invoice/receipt/card words | Single keyword can false-fire |
| `product_page` | commerce keywords OR furniture Vision + shop cues | OK-ish |
| `chat` | imessage/whatsapp/telegram/delivered/read /typing | **Misses** chats without app strings (Case A) |
| `social_post` | instagram/tiktok/liked by/… | Keyword-only |
| `design_reference` | figma/sketch/… | Keyword-only |
| `reservation` | reservation/booking/confirmed/opentable/… | Overlaps hotel/flight |
| `image_only` | empty OCR | Good abstention path |
| `interior_reference` / `travel_imagery` | image_only + Vision nouns | Level 1 assist — keep |

**Critical false-positive:** `"check-in"` alone → `hotel_booking` on Etihad manage-trip / boarding UIs.

**Critical false-negative:** Indonesian/WhatsApp UI with conversation structure but no “whatsapp” → no `chat`.

**Anti-pattern (forbidden):** `document` Vision label → any Level 2 type.

---

### Confidence / provenance representation (proposed)

Smallest workable model (in-memory first; persist if cheap):

```text
FacetEvidence {
  identifier: String           // chat, boarding_pass, …
  confidence: Float            // 0…1
  strength: strong | weak      // or map from confidence bands
  sources: [String]            // e.g. ocr_phrase, ocr_structure, entity_iata, vision_assist
}
```

**Emit policy:**

| Strength | When | Persist / cluster use |
|----------|------|------------------------|
| **strong** | ≥2 independent cue families agree, or one high-precision compound pattern | Yes — primary Level 2 evidence |
| **weak** | Single soft cue | DEBUG + optional downweight; may omit from “strong facets” list for grouping later |
| **unknown / abstain** | Conflict or insufficient | Prefer **no facet** (or explicit `unknown` only when useful for DEBUG) |

Conflict example: strong flight cues + lone “check-in” → **do not** emit strong `hotel_booking`.

Backward compatibility: consumers that need `[String]` can take **strong** identifiers only (or strong+weak with separate field). Prefer not breaking organize mid-8.2A — keep `visual_facets_json` as strong (and optionally weak) id list while DEBUG shows full evidence.

---

### Multi-signal scoring principles (not brittle keyword taxonomy)

- Single keyword may contribute **partial** score — **never sufficient alone** for strong facet  
- Combine: phrases, structure, entities (IATA, currency, totals), dates/times, domains/URLs, Vision as **weak** assist, UI/app cues when reliable  
- Cap vocabulary; abstain when below threshold  
- No Collection folders from types  

#### Case scoring sketches (8.2A)

| Case | Strong when | Abstain / weak when |
|------|-------------|---------------------|
| **A Chat** | App id **or** (message-like structure: short lines + repeated time-like tokens + conversational turns) + optional Vision document as weak only | Only `document` Vision; long prose; no structure |
| **B Flight** | Airport-code pattern + flight/terminal/boarding/passenger family (≥2) | “check-in” alone; hotel brands dominate |
| **B′ Hotel** | Hotel/guest/stay cues **without** dominant flight/IATA set | Airline check-in pages |
| **C Article / social** | Domain/platform **and** structure (long prose vs engagement chrome) | Ambiguous document UI → unknown |
| **D Receipt** | ≥2 of currency/total/tax/line-item/merchant patterns | Lone “total” |
| **E Map** | Directions/route/distance **or** Vision `map` + place/route text | Vision `map` alone → weak |
| **F Person / image** | Keep Level 1 descriptors; `image_only` if weak OCR | Never invent selfie/portrait/friend |

---

### Smallest 8.2A implementation (after plan APPROVAL)

1. Introduce `FacetEvidence` + `strength` scoring inside / beside `ScreenshotFacetDeriver`  
2. Replace binary OR-lists with **scored cue families** for: `chat`, `boarding_pass` / `flight_booking`, `hotel_booking`, `receipt`, `map` (highest device priority)  
3. Fix **check-in ∩ flight** collision (hotel suppressed when flight-dominant)  
4. Add conservative **chat structure** heuristic (not WhatsApp-only)  
5. Persist compatible facet id list (strong required; weak optional / DEBUG)  
6. Visual Eval: show facet + strength + short provenance  
7. Unit tests for Cases A–F fixtures (synthetic OCR strings)  
8. **Do not** change `MultiSignalClusterer` weights, resolver, Vision filter, or Collections  

**Likely files (when coding):**  
`ScreenshotFacetDeriver.swift`, small model types (same file or `MemoryModels`), `GRDBMemoryRepository.completeVisualSuccess` (if JSON shape changes), Visual Eval DEBUG, `VisualIntelligenceTests.swift`

**Explicitly not in 8.2A:** clustering redesign, Lab, embeddings, naming, Vision remaps.

---

### 8.2A physical-device test cases

Curate real shots; for each run Visual Eval + note facets after reprocess (or live facet DEBUG if added).

| ID | Shot class | Expect |
|----|------------|--------|
| A1 | WhatsApp / iMessage-like conversation | Strong or weak `chat` from structure/app; **not** Collection “Chat” |
| A2 | Chat without visible app name (if available) | `chat` if structure supports; else unknown — **not** forced |
| B1 | Etihad / airline manage-trip / boarding | Strong `boarding_pass` and/or `flight_booking`; **not** strong `hotel_booking` from check-in alone |
| B2 | True hotel booking (if available) | `hotel_booking` without false flight |
| C1 | LinkedIn / article-like | `article` or `social_post` only if strong; else unknown |
| D1 | Receipt / payment | Strong `receipt` with multi cues |
| E1 | Maps / directions | `map` strong when text/Vision agree |
| F1 | Person photo / image-heavy | Level 1 labels OK; no selfie facet; `image_only` if OCR empty |
| G1 | Ambiguous dense UI | Prefer unknown/weak over wrong confident type |
| H1 | Spot-check | No Collection titled after facet vocabulary |

**8.2A ACCEPT gate:** A1, B1, D1/E1 directional pass; B1 hotel false-positive fixed; C/F/G abstention OK; H1 pass; 8.1 Vision pipeline untouched.

Then **STOP** — wait for **ACCEPT 8.2A** before 8.2B.

---

## Sub-phase 8.2B — Context Candidate Grouping

**Detailed plan:** `reviews/sprint-08-2b-plan.md` (**PLAN ONLY** — do not implement until approved).

### Goal

Produce taxonomy-neutral **candidate groups** + cohesion from multi-signal evidence. **Stop before naming or Collection mutation.**

### Signals (no single signal defines a cluster)

OCR/entity overlap · **strong** facet compatibility (weak = soft only) · Vision (generic labels denylisted) · feature-print bands (soft) · time (**soft, never sufficient**) · existing Collection **profiles** as relatedness hints (≠ assignment)

### Example (illustrative only)

`flight_booking` + `hotel_booking` + `map` + `reservation` + image-heavy support → one candidate group, high cohesion → **STOP** (no dynamic title, no CREATE).

### 8.2B device gate (preview)

Related multi-type travel/context shots cohere; unrelated stay apart; time-only pairs do not group; FP/Vision alone do not invent context; facets never become Collection titles.

**Primary code:** `MultiSignalClusterer` (+ DEBUG cluster views).

---

## Working agreement

1. ~~Approve 8.2 plan → implement 8.2A → physical ACCEPT~~ **DONE**  
2. Approve **`reviews/sprint-08-2b-plan.md`** → implement **8.2B only** → tests → physical checklist → **STOP**  
3. Do not start 8.3A/8.3B/9 from this sprint  

---

## Status summary

| Phase | Status |
|-------|--------|
| 8.0 | ✅ CLOSED |
| 8.1 | ✅ CLOSED / ACCEPTED |
| **8.2A** | ✅ CLOSED / ACCEPTED |
| **8.2B** | 📋 PLAN ONLY — `reviews/sprint-08-2b-plan.md` |
| 8.3A+ / 9 | ⛔ NOT STARTED |
