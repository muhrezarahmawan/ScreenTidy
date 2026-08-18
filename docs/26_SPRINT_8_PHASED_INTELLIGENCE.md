# Sprint 8 — Phased Intelligence Roadmap

**Status:** Sprint 8 **OPEN** (phases **8.0** + **8.1** + **8.2A** + **8.2B CLOSED**; **8.3A** in progress) · Sprint 9 **NOT STARTED**  
**Date locked:** 2026-08-10  
**8.0 accepted:** 2026-08-10 (physical iPhone)  
**8.1 accepted:** 2026-08-10 (physical iPhone visual evidence evaluation)  
**8.2A accepted:** 2026-08-10 (physical iPhone — narrowed Level 2A structured typing gate)  
**8.2B accepted:** 2026-08-10 — **local precision-first candidate-grouping baseline** (`reviews/sprint-08-2b-completion-report.md`)  
**Active phase:** **8.3A — Multimodal Screenshot Understanding Lab** (`reviews/sprint-08-3a-plan.md`) — APPROVED  
**8.2B-R2b:** ❌ CANCELLED  
**8.3B+ / Sprint 9:** ⛔ NOT STARTED  
**Supersedes for sequencing:** Architecture C P0→P6 order in `reviews/intelligence-architecture-multisignal-proposal.md` (product rules still apply)  
**Resolver plan (thresholds/authority):** `docs/24_SPRINT_8_COLLECTION_RESOLVER.md`  
**Roadmap entry:** `docs/13_IMPLEMENTATION_ROADMAP.md` § Sprint 8  
**Code audit:** `reviews/sprint-08-phased-audit.md`  
**8.0 completion:** `reviews/sprint-08-0-completion-report.md`  
**8.1 completion:** `reviews/sprint-08-1-completion-report.md`  
**8.2A completion:** `reviews/sprint-08-2a-completion-report.md`  
**8.2B completion:** `reviews/sprint-08-2b-completion-report.md`  
**8.2 plan:** `reviews/sprint-08-2-plan.md`  
**8.2B plan:** `reviews/sprint-08-2b-plan.md`  
**8.3A plan:** `reviews/sprint-08-3a-plan.md`

---

## Dynamic Collection Invariant (LOCKED)

ScreenTidy has **no predefined Collection taxonomy**.

Collection identity and Collection names are **dynamically inferred** from the actual shared context of screenshots. The Collection namespace is **open-ended**: the product must be able to discover contexts that neither developers nor prompts anticipated.

Any Collection names used in documentation, planning, examples, tests, or discussions (e.g. “Japan Trip”, “Apartment Setup”, “Visa Application”) are **illustrative examples only**. They must **not** become:

- hardcoded categories  
- canonical Collection names  
- taxonomy seeds  
- fallback Collection names  
- clustering labels  
- few-shot answers that bias the LLM toward specific names  
- exact expected benchmark strings  
- assumptions about what Collections users should have  

### Intended intelligence model

```
screenshots
    ↓
extract local evidence
(OCR + Vision + metadata + similarity + other signals)
    ↓
determine which screenshots likely belong together
    ↓
infer the shared real-world context
    ↓
compare that inferred context against existing Collection profiles
    ↓
┌───────────────────────────┐
│ Existing context matches? │
└───────────────────────────┘
        ↓ YES        ↓ NO
       REUSE        CREATE
       existing      new Collection with
       Collection    dynamically inferred name
            ↓          ↓
             local resolver
                   ↓
             final decision
```

**Reuse-before-create** means: *Does this new context match something the user already has?*  
**Not:** *Which predefined category does this screenshot belong to?*

Existing Collections are **context profiles for REUSE**. They must not become a global taxonomy that constrains what new Collections can exist.

### Evidence ≠ Collection

| Layer | Question | Must NOT |
|-------|----------|----------|
| Local evidence | What is visible? (OCR, Vision nouns, metadata, similarity) | Define the Collection taxonomy |
| Internal facet | What type of content is this? | Become a Collection title |
| Contextual intelligence | What do these screenshots mean **together**? | Be skipped in favor of noun folders |
| Dynamic naming | What should the Collection be called? | Come from a fixed name list |

Apple Vision labels / facets and OCR entities are **evidence only**. Contextual inference and naming belong to later multimodal / resolver phases.

### Dynamic naming & evaluation

When CREATE is appropriate, multimodal intelligence should generate a name **grounded in evidence**. There is no fixed list of valid names. Different names can be semantically equivalent and equally correct.

Future evaluation (e.g. Sprint **8.5** Benchmark v1) must **not** require exact string equality for Collection names. Evaluate instead:

- grouping correctness  
- inferred context correctness  
- reuse vs create correctness  
- grounding · specificity · usefulness of the generated name  
- hallucination avoidance  

If evidence is insufficient to infer a meaningful context → **Needs Review**.  
Do **not** invent a generic Collection merely to increase coverage.

---

## Product goal (locked)

Automatically organize screenshots into meaningful **personal context** Collections — discovered from the user’s real screenshots, not selected from a developer taxonomy.

| Illustrative good context *(examples only)* | Bad (type / Vision-noun folders) |
|---------------------------------------------|----------------------------------|
| e.g. a personal trip context | Flights / Hotels / Maps / Buildings |
| e.g. a home-setup project context | Furniture / Products / Interior |
| e.g. an application paperwork context | Documents / Travel |

Vision nouns and type facets are **evidence only** — never Collection titles.

---

## Working agreement (locked)

1. Work **one** Sprint 8.x phase at a time.
2. After each phase: build → tests → completion report → physical-device checklist → **STOP**.
3. Wait for explicit **ACCEPT** before the next phase.
4. If device verification fails: keep that phase **OPEN**; do not advance.
5. Do **not** lower assign ≥ **0.70** / create ≥ **0.85** + corroboration.
6. Railway / hosting: **paused** unless a later Lab phase explicitly needs a hosted endpoint.
7. Embeddings: **Sprint 8.7 only if needed** — not before multimodal contextual reasoning is proven.

---

## Phases

| Phase | Name | Goal | Status |
|-------|------|------|--------|
| **8.0** | Intelligence Foundation Health | OCR + Visual queues process reliably on device | **CLOSED / ACCEPTED** (2026-08-10) |
| **8.1** | Visual Understanding | Useful Vision Level 1 evidence; never Collection names | **CLOSED / ACCEPTED** (2026-08-10) |
| **8.2** | Multi-Signal Content Typing + Context Candidate Grouping | Level 2A facets → Level 2B grouping | **8.2A CLOSED**; **8.2B IMPLEMENTED** (awaiting physical ACCEPT) |
| **8.3** | Intelligence Lab | DEBUG multi-image multimodal; **no** Collection mutation | **NOT STARTED** |
| **8.4** | Prompt + Schema Refinement | Iterate Lab prompt/schema for contextual naming | **PARTIAL** (gateway only) |
| **8.5** | Intelligence Benchmark v1 | 30–50 shot measurable product-quality set | **NOT STARTED** |
| **8.6** | Production Organization Integration | Proven Lab → resolver → GRDB → UI | **PARTIAL** (per-shot path exists) |
| **8.7** | Embeddings (conditional) | Only if retrieval/grouping is the bottleneck | **NOT STARTED** / **DEFER** |
| **8.8** | Backlog, Scale, Performance, Cost | Scale proven intelligence | **PARTIAL** (early caps only) |

---

### 8.0 — Intelligence Foundation Health *(CLOSED / ACCEPTED)*

**Delivered:** Visual queue lifecycle (strong worker retention, claim → complete/fail/inaccessible), claimability diagnostics, Kick parity, reprocess clearing, PhotoKit timeout as transient, split classify/feature-print with partial success, fine-grained errors + DEBUG failure tools.

**Device gate (passed):** Pending/Claimable/Processing → 0; Completed persists across relaunch; Failed → 0 after remediation; continuous drain after one Kick.

**Report:** `reviews/sprint-08-0-completion-report.md`

---

### 8.1 — Visual Understanding *(CLOSED / ACCEPTED)*

**Delivered:** DEBUG Visual Intelligence evaluation (persisted vs Live classify RAW→FILTERED, neighbors/FP, paginated completed browse). Physical eval confirmed Vision as useful **Level 1 supporting evidence** with known generic-label limitations; screenshot-type inference deferred.

**Report:** `reviews/sprint-08-1-completion-report.md`

---

### 8.2 — Multi-Signal Content Typing + Context Candidate Grouping

Driven by 8.1 finding: Vision often yields generic Level 1 labels (`document`, …). **Do not** force Vision to emit semantic types.

- **8.2A** — Local high-confidence **structured** content typing + confidence/abstain — **CLOSED / ACCEPTED** (`reviews/sprint-08-2a-completion-report.md`)  
  - Precision + honest abstention; **not** full screenshot-type coverage  
  - Visually semantic types (notification_center, video_call, portrait, gameplay, hard social vs article) → **8.3A multimodal** — do **not** expand deriver rules  
- **8.2B** — Context candidate grouping — **CLOSED / ACCEPTED** as local baseline (`reviews/sprint-08-2b-completion-report.md`) — no Collection naming  

**Parent plan:** `reviews/sprint-08-2-plan.md`

### 8.3 — Intelligence Lab / multimodal understanding *(8.3A APPROVED)*

Split intent (architecture reassessment 2026-08-10):

- **8.3A** — Multimodal **screenshot content understanding** for ambiguous / visually semantic types — **APPROVED** `reviews/sprint-08-3a-plan.md`  
- **8.3B+** — Multimodal **contextual group reasoning** → resolver — **NOT STARTED**  

DEBUG Lab: select shots → structured content proposals → manual labels → **zero** Collection mutation until proven.

### 8.4 — Prompt + Schema Refinement

Improve Lab naming, reuse-before-create, confidence, ambiguity → Needs Review.

### 8.5 — Benchmark v1

Fixed 30–50 real screenshots; track correct assign, wrong confident, reuse, create, naming usefulness, NR, image-only. Targets: ≥85% correct among auto-filed; <5% confidently wrong; ≥80% correct reuse; trust > coverage.

**Naming evaluation:** judge grounding / specificity / usefulness / equivalence — **not** exact match to illustrative doc titles. Do not seed the benchmark with a closed Collection name list.

### 8.6 — Production Integration

Candidate group → multimodal proposal → **local** Collection Resolver → mutate. Cloud never writes Collections. Thresholds unchanged.

### 8.7 — Embeddings *(if needed)*

Prefer local text embeddings. No cloud vector DB. Only after Lab proves grouping/retrieval is the gap.

### 8.8 — Scale / Cost

Hundreds–thousands; incremental analysis; batching; caching; battery. Only after quality works.

---

## Authority stack (locked)

1. Apple Vision = perception / evidence
2. Multimodal LLM = deep contextual understanding
3. Collection Resolver = local trust authority
4. User = ultimate authority (`source=user`)

---

## Explicitly paused / deferred

| Item | Decision |
|------|----------|
| Railway deploy / LAN gateway debugging | **Paused** |
| P3 embeddings before Lab | **Deferred → 8.7 conditional** |
| Sprint 9 | **Not started** |
| Lowering resolver thresholds | **Forbidden** |
| Sprint 8.2A implementation | **CLOSED / ACCEPTED** — see `reviews/sprint-08-2a-completion-report.md` |
| Sprint 8.2B | **CLOSED / ACCEPTED** — local candidate-grouping baseline (`reviews/sprint-08-2b-completion-report.md`); R2b cancelled |
| Sprint 8.3A multimodal content understanding | **APPROVED / implementing** — `reviews/sprint-08-3a-plan.md` |
