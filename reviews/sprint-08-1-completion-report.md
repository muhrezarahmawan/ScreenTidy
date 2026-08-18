# Sprint 8.1 — Visual Understanding — Completion Report

**Status:** **CLOSED / ACCEPTED**  
**Accepted:** 2026-08-10 (physical iPhone evaluation)  
**Canonical phase plan:** `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md`  
**Sprint 8 overall:** remains **OPEN / NOT ACCEPTED** until later phases land  
**Next phase:** **8.2 — Multi-Signal Content Typing + Context Candidate Grouping** (plan only — do not implement until explicit plan APPROVAL)  
**Sprint 9:** **NOT STARTED**

---

## Goal (as accepted)

Prove Apple Vision provides useful **supporting Level 1 visual evidence** for later multi-signal reasoning — **not** final screenshot semantics, content-type naming, or Collection titles.

Acceptance was **not**: “Vision correctly names every screenshot type.”

---

## Acceptance gate (PASSED)

| Criterion | Result |
|-----------|--------|
| Vision pipeline healthy (post–8.0 queue + classify/FP) | Pass |
| RAW / FILTERED evaluation trustworthy (Live classify authoritative; persisted vs live separated) | Pass |
| Generic / noisy Level 1 behavior understood and documented | Pass |
| Distinctive labels preserved when Vision provides them | Pass (directional) |
| Feature prints usable as visual similarity evidence | Pass (DEBUG neighbors) |
| Image-heavy shots can gain some local evidence **or** honest abstention | Pass |
| Safe abstention allowed when Vision has little distinctive signal | Pass |
| Vision nouns / facets never become Collection titles | Pass (policy + tests + no 8.1 title path) |
| Sprint 8.0 queue health remains stable | Pass (unchanged foundation) |

Formal sample size (~10–20 curated diverse shots) was used for qualitative judgment. Browsing the full completed library was tooling support only.

---

## Physical evaluation findings (product / architecture learnings — not 8.1 bugs)

1. **Generic text-heavy UIs** often yield Level 1 `document` (sometimes high confidence). Technically plausible; **not** screenshot-type understanding.
2. **People / photos** often yield `adult`, `clothing`, `eyeglasses`, `structure`, and similar object descriptors — useful as visual descriptors when distinctive; often generic for organization.
3. **Some image-only screenshots** produce **no useful surviving filtered labels**. Acceptable abstention when Vision has little distinctive evidence.
4. These are **known limitations of Level 1 Vision evidence**, not defects to “fix” by forcing more specific Vision nouns.
5. Vision **must not** be expected to infer Level 2 types (`chat`, `article`, `boarding_pass`, `flight_booking`, `receipt`, `map`, …).
6. More specific screenshot-type understanding belongs in **Sprint 8.2+** multi-signal facet / grouping work (OCR + structure + Vision + FP + time + profiles) — **not** `document → chat` Vision remaps.
7. OCR-derived **internal facets** (e.g. boarding_pass / hotel_booking on travel UIs) already demonstrate Level 2 can come from text while Vision stays at `document`. Facet quality / confidence / collisions are **8.2+**, not 8.1 reopen criteria.
8. **Dynamic Collection Invariant** unchanged: facets and Vision nouns remain evidence only; Collection naming stays open-ended and downstream.

### Three semantic levels (locked learning)

| Level | Question | Sprint 8.1 role |
|-------|----------|-----------------|
| **1** What is visible? | Vision labels / FP | **In scope — evaluated** |
| **2** What kind of content? | Internal facets (multi-signal) | Observed existing; **improved in 8.2** |
| **3** What shared real-world context? | Later multimodal + resolver | **Deferred (8.3+)** |

---

## What shipped in Sprint 8.1 (engineering)

1. DEBUG Visual Intelligence inspector (raw vs filtered, drops, facets, FP, neighbors, cluster diagnostics)
2. Live classify as authoritative RAW → FILTERED comparison (does not persist)
3. Persisted vs live sections; empty-RAW messaging when filtered exists
4. Paginated browse of all completed Visual analysis (lightweight list; detail on demand)
5. Progressive high-quality preview for Visual Eval / fullscreen (list thumbs stay light)
6. Separate visual long-edge (1024) vs OCR (1800) documented and used
7. Optional DEBUG filter override (does not change production defaults)
8. Tests for queue, filter, pagination, DEBUG messaging

**Explicitly not done in 8.1:** strong/weak/noise production Vision policy expansion; screenshot-type classifier; chat/article/boarding inference from Vision; clustering weight redesign; resolver threshold changes; Lab; embeddings; Railway; Collection naming.

---

## Explicitly out of scope (deferred)

| Item | Destination |
|------|-------------|
| Multi-signal content typing + facet confidence | **8.2** |
| Context candidate grouping quality | **8.2** |
| Intelligence Lab | **8.3** |
| Prompt / schema / multimodal naming | **8.4+** |
| Embeddings | **8.7 conditional** |
| Resolver threshold changes | Forbidden / later only with explicit ACCEPT |
| Sprint 9 | **NOT STARTED** |

---

## Follow-on

See **`reviews/sprint-08-2-plan.md`**. Do **not** implement Sprint 8.2 until the plan is **explicitly approved**.
