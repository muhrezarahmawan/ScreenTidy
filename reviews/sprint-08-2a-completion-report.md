# Sprint 8.2A — Local High-Confidence Structured Content Typing — Completion Report

**Status:** **CLOSED / ACCEPTED**  
**Accepted:** 2026-08-10 (physical iPhone — narrowed Level 2A gate)  
**Canonical phase plan:** `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md`  
**Detailed plan:** `reviews/sprint-08-2-plan.md`  
**Next:** **Sprint 8.2B — Candidate Grouping** (`reviews/sprint-08-2b-plan.md`) — **PLAN ONLY** until explicit plan APPROVAL  
**Sprint 9:** **NOT STARTED**

---

## Goal (as accepted)

Ship a **local Level 2A** layer that answers:

> What kind of **structured** screenshot content is this — when local OCR/structure evidence is sufficient?

Success = **precision + honest abstention**, **not** coverage of every screenshot type.

Level 2A facets are **internal evidence only**. They must **never** become Collection names or define a Collection taxonomy (**Dynamic Collection Invariant**).

---

## Architectural role (locked)

```
Level 1   Vision nouns / feature prints     → 8.1 CLOSED
Level 2A  Local high-confidence structured typing → 8.2A CLOSED (this report)
Level 2B  Candidate grouping                 → 8.2B PLAN
Level 2C  Multimodal screenshot understanding → 8.3A (later)
Level 3+  Contextual Collection intelligence → 8.3B+
```

**8.2A owns (high precision when evidence agrees):**  
`boarding_pass`, `flight_booking`, `hotel_booking`, `receipt`, `map`, strong `chat` (dialogue evidence), and other structured OCR types already in the deriver.

**Explicitly deferred to Sprint 8.3A multimodal** (do **not** expand `ScreenshotFacetDeriver` with special-case rules):

- `notification_center`
- `video_call`
- `portrait` / `person_photo`
- `gameplay`
- difficult `social_post` vs `article`
- other visually semantic / ambiguous app UIs

A `—` (abstain) result for those cases is **acceptable** at the 8.2A layer.

---

## Narrowed physical acceptance gate (PASSED)

| Case | Required | Result |
|------|----------|--------|
| Real boarding / flight | strong `boarding_pass` / `flight_booking` | ✅ |
| Airline check-in | **not** `hotel_booking` | ✅ |
| Real hotel reservation | strong `hotel_booking` when lodging evidence agrees | ✅ |
| Real multi-turn chat | strong `chat` when dialogue evidence agrees | ✅ |
| Notification Center | **no** false chat; abstention OK | ✅ |
| Vision `document` alone | never defines Level 2 type | ✅ (policy + regressions) |

Additional acceptable abstentions observed during development (not failures of the narrowed gate): portrait, gameplay, video-call / sparse OCR without inventing semantic `image_only`.

---

## Physical-device findings (product learnings)

1. **Structured OCR types** (boarding / flight, clear hotel, multi-turn dialogue chat) can reach trustworthy **strong** facets locally with cue-family diversity — without lowering `strongFloor` (0.72).
2. **Airline check-in ≠ hotel** remains a critical regression; flight-dominant suppression + lodging diversity gates protect it.
3. **Notification Center must not become chat.** Feed/card structure vs dialogue structure discrimination is required; abstention is correct when not a conversation.
4. **Visually semantic types** (video call, portrait, gameplay, NC-as-type) are **not** realistic to solve well with OCR keyword/regex rules alone. Expanding the deriver for coverage would create brittle debt.
5. Empty/sparse OCR is an **analysis state**, not a semantic content type. Semantic `image_only` was removed from Level 2 FacetEvidence; sparse OCR remains DEBUG/pipeline metadata.
6. **Wrong strong ≫ missing facet.** Abstention for unsupported/ambiguous screenshots is a successful 8.2A outcome.
7. **Dynamic Collection Invariant** unchanged: facets never title Collections; open-ended Collection identity stays downstream (8.3+ multimodal + resolver).

---

## What shipped in Sprint 8.2A (engineering summary)

1. Scored `FacetEvidence` (id, confidence, strength strong|weak, sources) via `ScreenshotFacetDeriver`
2. Strong = score ≥ 0.72 **and** ≥ 2 independent cue families (high-risk facets)
3. Flight/boarding evidence diversity + tighter IATA / flight-number patterns
4. Hotel lodging / stay-date / reservation / property families (no threshold cut)
5. Chat dialogue-positive vs feed/notification-negative structure
6. Conflict: strong travel suppresses structure-only chat; flight-dominant suppresses hotel
7. Persistence of strong facet IDs + full evidence JSON; Visual Eval DEBUG provenance
8. Regression fixtures for structured typing + abstention / anti-false-positive cases

**Explicitly not done in 8.2A:** notification_center / video_call / gameplay / portrait vocabulary expansion; MultiSignalClusterer redesign (8.2B); Collection naming; Lab; embeddings; Railway; resolver threshold changes.

---

## Follow-on

1. Read **`reviews/sprint-08-2b-plan.md`** (candidate grouping — plan only).  
2. Do **not** implement 8.2B until that plan is **explicitly approved**.  
3. Do **not** start 8.3A multimodal content understanding from this acceptance alone.
