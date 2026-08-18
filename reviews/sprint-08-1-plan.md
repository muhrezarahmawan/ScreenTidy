# Sprint 8.1 — Visual Understanding — Plan

**Status:** **CLOSED / ACCEPTED** (2026-08-10 — physical-device evaluation)  
**Completion report:** `reviews/sprint-08-1-completion-report.md`  
**Depends on:** Sprint **8.0 CLOSED / ACCEPTED** (`reviews/sprint-08-0-completion-report.md`)  
**Canonical roadmap:** `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md`  
**Next:** Sprint **8.2** plan — `reviews/sprint-08-2-plan.md` (**PLAN ONLY** until approved)

---

## Dynamic Collection Invariant (LOCKED)

See `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md` § Dynamic Collection Invariant.

**Sprint 8.1 role (completed):** judge whether Vision provides useful **Level 1 visual evidence** for later multi-signal reasoning — **not** whether Vision invents screenshot types or Collection titles.

---

## Goal (accepted)

Evaluate whether Apple Vision produces **useful supporting visual intelligence** for real screenshots — quality of Level 1 evidence for later contextual grouping — **not** queue infrastructure and **not** Level 2 content typing.

**Hard product rule:** Vision labels are **evidence only**. They must **never** directly become Collection names.

---

## Acceptance criteria (physical iPhone) — PASSED

See completion report for full findings. Summary:

| # | Criterion | Result |
|---|-----------|--------|
| A | Filtered labels plausibly useful as supporting evidence (not Collection titles) | Pass (directional) |
| B | Remaining generic/noise understood via DEBUG / Live classify | Pass |
| C | Feature-print neighbors useful as visual similarity | Pass (qualitative) |
| D | Image-only: useful labels **or** honest abstention | Pass |
| E | Vision nouns never become Collection titles | Pass |
| F | Production auto-organize / resolver thresholds unchanged | Pass |
| G | Evaluation notes recorded | Pass (`sprint-08-1-completion-report.md`) |

Sprint 8.1 did **not** require Vision to classify chat / article / boarding_pass / etc.

---

## Delivered engineering (summary)

DEBUG Visual Intelligence tooling; Live classify authoritative RAW→FILTERED; persisted vs live separation; paginated completed-shot browse; progressive Visual Eval preview; visual vs OCR long-edge separation; DEBUG filter override; focused tests.

---

## Explicitly deferred (not 8.1 reopen)

Multi-signal content typing, facet confidence, candidate grouping quality → **Sprint 8.2**. Lab / multimodal / embeddings / Railway / naming / Sprint 9 → later phases.
