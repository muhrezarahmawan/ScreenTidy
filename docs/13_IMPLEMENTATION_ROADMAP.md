# ScreenTidy — Implementation Roadmap (MVP → TestFlight)

**Status:** **Approved** — official engineering roadmap  
**Source of truth for product/architecture:** `docs/00`–`12`, working agreement `docs/14_WORKING_AGREEMENT.md`  
**Rule:** Implementation follows documentation unless docs are explicitly revised.

This roadmap starts from an **empty SwiftUI project** and ends at a **TestFlight-ready MVP**. It is optimized for **rapid design iteration**: Design System → interactive UI with mocks → modular real backends.

---

## Guiding engineering principles

1. **UI early** — Designer can tap through real navigation with mock memories ASAP.  
2. **Design System before business logic** — tokens/components stabilize visual rework.  
3. **Protocol-first modules** — `PhotosProviding`, `ScreenshotStoring`, `Organizing`, `Searching`, `CleaningUp` with mock implementations first.  
4. **Persistence before Photos write-path** — avoid in-memory import rework.  
5. **OCR + Search before cloud AI** — magical local find works without gateway.  
6. **Manual contexts before AI** — product usable if AI slips.  
7. **Minimize rework** — no “throwaway” screens; mocks back the same views.

---

## Recommended sprint order (revised)

Your proposed order is strong on design-first intent. These changes reduce rework and match the architecture docs’ build sequence:

| Change | Why |
|--------|-----|
| **SQLite before Photos import persistence** | Importing into memory then re-plumbing to DB is expensive rework. |
| **Search immediately after OCR** | FTS is core UX and demoable without AI; your Sprint 7 was too late. |
| **Manual Context Collections before AI Organization** | Resolver/AI attaches to a real collection graph; app works offline/no-consent. |
| **Cleanup after organization signals exist** | Still late-ish, but after facets/entities/dates and pHash from thumbs. |
| **Split “complete UI” realism** | Sprint 2 = all primary flows + happy paths; edge-state perfection waits for polish. |

### Revised sequence

| Sprint | Name |
|--------|------|
| 0 | Project Foundation |
| 1 | Design System (+ Home pilot) |
| 2 | Full UI Shell + Mock Data |
| 3 | Local Database (SQLite + FTS schema) |
| 4 | Photo Library Integration |
| 5 | OCR Pipeline |
| 6 | Search (FTS wired) |
| 7 | Manual Memory Organization |
| 8 | AI Organization Engine |
| 9 | Cleanup |
| 10 | Performance, Polish & Hardening |
| 11 | TestFlight MVP |

> Net: **11 sprints** vs 10 — Search and Manual Organization earn their own slots; TestFlight stays last. Calendar length need not grow if Sprint 2 is scoped tightly and AI gateway is stubbed early.

---

## Milestone map

```
M0 Foundation
M1 Interactive prototype (DS + mock UI)     ← Designer primary feedback loop
M2 Real library on device (DB + Photos + OCR + Search)
M3 Memory organization (manual + AI)
M4 Cleanup + ship quality
M5 TestFlight
```

---

## Sprint 0 — Project Foundation

### Goal
Create a clean, modular Xcode workspace ready for SwiftUI features without painting the team into a corner.

### Deliverables
- Xcode project (iOS **17+**), app target, folder structure by feature/layer  
- Dependency boundaries: `App`, `DesignSystem`, `Features/*`, `Domain`, `Data`, `Services`  
- Protocol stubs for core ports (store, photos, organize, search, cleanup)  
- App entry + tab shell placeholder (can be unstyled)  
- Build configurations (Debug/Release), basic `.gitignore`, project README pointing at `/docs`  
- Decision: package manager for GRDB (or chosen SQLite layer) recorded  

### Dependencies
- None (empty repo aside from docs)

### Risks
- Over-engineering folders before UI exists  
- Picking SwiftData “just for now” against locked SQLite decision  

### Estimated complexity
**S** (0.5–1.5 days)

### Definition of Done
- [x] App project + tab shell with mock-backed feature screens
- [x] Module/folder conventions documented in repo README
- [x] iOS 17 deployment target set
- [x] No product code that contradicts Option C docs
- [x] GRDB recorded as Sprint 3 persistence choice (`docs/15_SPRINT_0_NOTES.md`)
- [ ] Build verified on a Mac with full Xcode (environment used for scaffolding had CLT only)

---

## Sprint 1 — Design System (+ Home pilot)

### Goal
Establish visual language and reusable components so all screens share one look; prove it on Home.

### Deliverables
- Tokens: spacing (24pt page), radius, typography, colors, shadows  
- Components: `FloatingTabBar`, `SearchField`, `ContextCollectionCard`, `ScreenshotGridItem`, `EmptyState`, `PrimaryButton`, sheets chrome  
- Motion primitives (with Reduce Motion hook points)  
- **Home pilot** using **inline mock** Context Collections (Japan Trip, etc.) + Unassigned teaser  
- Light/dark if required by system; follow visual direction (prefer light calm default)  

### Dependencies
- Sprint 0

### Risks
- Designing every component before any screen → abstract DS  
- Card collage complexity blocking the sprint  

### Estimated complexity
**M** (2–4 days)

### Definition of Done
- [x] Designer can review Home pilot on device/simulator  
- [x] Cards use collage metaphor (mock images OK) — no folder icons  
- [x] Tokens match `10_DESIGN_SYSTEM.md` / `04_VISUAL_DIRECTION.md`  
- [x] Components reusable without feature-layer business logic  

**Sprint 1 status:** Complete (2026-08-08) — see `reviews/sprint-01-review.md`, `docs/17_SPRINT_1_DESIGN_SYSTEM.md`

### Goal
Ship an end-to-end **tappable product** with mock repositories so UX can be validated before Photos/AI.

### Deliverables
- Tabs: Home, Search, Cleanup, Settings  
- Screens: Onboarding (full flow UI), Context Detail, Screenshot Detail, Search, Cleanup, Settings  
- Sheets: rename, merge (UI), move/add to context, dual delete confirmations, permission recovery (UI)  
- `MockScreenshotRepository` / `MockOrganizationRepository` with rich fixtures (multi-context, Unassigned, facets/entities in detail)  
- Navigation wiring per `05_INFORMATION_ARCHITECTURE.md`  
- Home promotion threshold demonstrated with mock counts  

### Dependencies
- Sprint 1

### Risks
- Boiling the ocean on every empty/error state  
- Mock models drifting from eventual DB schema  

### Estimated complexity
**L** (4–7 days)

### Definition of Done
- [ ] Designer can walk onboarding → home → context → detail → search → cleanup → settings without crashes  
- [ ] Copy feels like memory organizer (not taxonomy folders)  
- [ ] All views depend on protocols/mocks — no Photos/AI required  
- [ ] Domain mock models mirror planned entities (Screenshot, ContextCollection, Facet, Entity)  

---

## Sprint 3 — Local Database (SQLite + FTS)

### Goal
Stand up the system of record and repository implementations behind the same protocols used by UI mocks.

### Deliverables
- [x] GRDB stack, migrations **v1**  
- [x] Core tables: screenshots, contexts, memberships, duplicate groups, app_meta  
- [x] FTS5 virtual table foundation (population deferred to Search sprint)  
- [x] `GRDBMemoryRepository` implementing repository protocols  
- [x] Seed Needs Review singleton + fixture Collections (one-time)  
- [x] DEBUG reset / reseed (Settings → Developer)  
- [x] DI uses GRDB as default (MockMemoryStore retained for Previews)  

### Dependencies
- Sprint 0–2 (protocols + UI models).

### Risks
- Migration mistakes early  
- FTS sync bugs causing stale search later  

### Estimated complexity
**M–L** (3–5 days)

### Definition of Done
- [x] CRUD for screenshots/contexts/memberships works in unit tests  
- [x] State survives app relaunch  
- [x] Undo restores persisted metadata mutations  
- [ ] FTS table updates on write paths — **deferred** (foundation only in v1)  
- [x] Schema matches Sprint 3 persistence doc (`19_SPRINT_3_PERSISTENCE.md`)  

**Status:** Complete — see `docs/19_SPRINT_3_PERSISTENCE.md` and `reviews/sprint-03-review.md`.

---

## Sprint 4 — Photo Library Integration (READ / SYNC)

### Goal
**“These are now my real screenshots.”**  
Bytes stay in Apple Photos; ScreenTidy persists metadata + shows real thumbnails.  
**Not** production Photos deletion/mutation.

### Deliverables
- PhotoKit authorization (`.readWrite` least privilege for enumerate/read; no delete APIs called)  
- Screenshot discovery (screenshot subtype) + GRDB v2 identity (`source`, `access_state`)  
- One-time fixture → Photos handoff (preserve Collections)  
- Incremental reconcile + `PHPhotoLibraryChangeObserver` + pull-to-refresh / foreground  
- `ThumbnailProviding` → `PHCachingImageManager`; fullscreen viewer + share  
- Limited = inaccessible (keep memberships); Full missing = remove metadata  
- Real onboarding import / empty; Settings Limited manage  
- Scale-safe Home Needs Review (count + 3 peeks); paged galleries  
- Search: real thumbs + temporary mock ranking (not final intelligence)  
- Cleanup: metadata-only remove wording; **no** PhotoKit deletion  

### Dependencies
- Sprint 3 (DB), Sprint 2 (UI)

### Risks
- Limited Library shrink vs true delete  
- Large libraries / iCloud-backed assets  
- Permission edge cases  

### Estimated complexity
**L** (4–6 days)

### Definition of Done
See `docs/20_SPRINT_4_PHOTOS.md` (22-item revised DoD). Canonical: no PhotoKit deletion; no OCR/FTS/AI/network.

**Status:** **CLOSED / ACCEPTED** (2026-08-08). Physical-device verification recorded in `reviews/sprint-04-review.md`.

---

## Sprint 5 — On-Device Screenshot Understanding Foundation (OCR)

### Goal
**“Screenshots are locally understandable.”**  
Apple Vision OCR → local GRDB text + FTS substrate for Sprint 6 Search.  
**Not** automatic Collection organization.

### Deliverables
See canonical plan: `docs/21_SPRINT_5_OCR.md` (Vision APIs, queue, schema `v3_ocr`, retries, privacy, DoD).

Summary:
- Vision OCR service + bounded background queue (newest first)  
- Persist `ocr_text` / status / retry fields; populate `screenshot_fts`  
- Incremental OCR after Photos sync; offline; no OCR chrome on production gallery/viewer  
- DEBUG inspector for verification  

### Dependencies
- Sprint 4 (**CLOSED / ACCEPTED**)

### Risks
- CPU/battery on large libraries  
- iCloud remote-only assets (retryable load failures)  
- Language / empty-text quality  

### Estimated complexity
**M–L** (3–5 days)

### Definition of Done
See `docs/21_SPRINT_5_OCR.md` (14-item DoD). Canonical: on-device only; no auto-organize; no PhotoKit deletion.

**Status:** **CLOSED / ACCEPTED** (2026-08-08). Physical-device verification **PASSED**. Recorded in `reviews/sprint-05-review.md` and `reviews/sprint-05-completion-report.md`.


## Sprint 6 — Search (FTS Wired)

### Goal
Deliver the core “find a memory in seconds” experience on real local data (OCR first; facets/entities later enrich).

**Milestone:** User can find real screenshots by typing remembered text — offline, from local FTS.

**Not:** Automatic Collection organization / filing out of Needs Review.  
**Not:** AI classification or cloud search.

### Deliverables
Canonical plan: `docs/22_SPRINT_6_SEARCH.md` (**CLOSED / ACCEPTED**).

Summary (roadmap):
- SearchService over FTS5  
- As-you-type debounce, ranking boosts (recency/favorites)  
- Filters UI wired (context when present; favorites)  
- Zero-query: recent + context shortcuts  
- Match rationale v1 (user-facing caption; Collection title matches)  
- Search tab uses live DB / FTS, not mock substring scoring  

### Dependencies
- Sprint 3 + 5 (**CLOSED / ACCEPTED**) and 4 for real thumbs. Context filters expand in Sprint 7–8.

### Risks
- Expecting “magical” results before AI keywords/entities exist  
- Query performance regressions  

### Estimated complexity
**M** (2–3 days)

### Definition of Done
- [x] Querying visible OCR text returns correct screenshots offline (automated + device)  
- [x] Empty/error states acceptable  
- [x] Designer can demo find-by-text on a real device library  
- [x] No automatic Collection / Needs Review mutations from Search  
- [x] Sprint 7+ organization / AI work not started during Sprint 6  

**Status:** **CLOSED / ACCEPTED** (2026-08-08). Physical-device verification **PASSED**. Recorded in `reviews/sprint-06-review.md` and `reviews/sprint-06-completion-report.md`.

## Sprint 7 — Manual Memory Organization

### Goal
Make Context Collections a real, user-steerable memory graph **without** cloud AI.

**Canonical plan:** `docs/23_SPRINT_7_MANUAL_ORGANIZATION.md` (**APPROVED** 2026-08-08 — Phase A + B only).

### In scope (approved)
- Assignment spine: Needs Review / Collection Move (+ Create & Move), multi-select, Undo  
- Multi-context: Add to Collection, Remove from Collection  
- Needs Review orphan invariant; `source = user` provenance  

### Explicitly deferred (backlog — not Sprint 7)
- Pin / Archive / Merge / aliases (former Phase C)  
- Favorites / advanced peek ranking (former Phase D)  

### Deliverables (roadmap — Sprint 7 slice)
- Create / rename Context Collections (existing)  
- Manual add/remove membership; multi-context  
- Unassigned as review inbox (manual assign out)  

### Dependencies
- Sprint 3–6 (**CLOSED / ACCEPTED**)

### Risks
- Multi-select Undo graph correctness  
- Import sync must not re-orphan user-filed shots into Needs Review incorrectly  

### Estimated complexity
**M** (2–4 days) with Phase C/D deferred

### Definition of Done
- [x] Needs Review → Collection Move (+ Create & Move) production-backed  
- [x] Collection → Collection Move; Add; Remove; NR invariant  
- [x] Undo restores exact prior membership graph; `source = user`  
- [x] PhotoKit / OCR / FTS preserved; no Sprint 8 AI  
- [x] Phase C/D not implemented  
- [x] Automated tests + device checklist  
- [x] Physical-device verification **PASSED**  

**Status:** **CLOSED / ACCEPTED** (2026-08-08). Physical-device verification **PASSED**. Recorded in `reviews/sprint-07-review.md` and `reviews/sprint-07-completion-report.md`.

## Sprint 8 — Automatic Organization / Contextual Intelligence

### Goal
Deliver ScreenTidy’s core USP: understand screenshots and file them into meaningful **personal context** Collections when confident — with Needs Review as the uncertainty fallback.

**Canonical phased plan:** `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md` (Sprint **8.0–8.8**)  
**Dynamic Collection Invariant (LOCKED):** no predefined Collection taxonomy — see `docs/26_…` § Dynamic Collection Invariant  
**Resolver rules / thresholds:** `docs/24_SPRINT_8_COLLECTION_RESOLVER.md`  
**Code audit:** `reviews/sprint-08-phased-audit.md`  
**8.0 completion:** `reviews/sprint-08-0-completion-report.md`  
**8.1 completion:** `reviews/sprint-08-1-completion-report.md`  
**8.2A completion:** `reviews/sprint-08-2a-completion-report.md`  
**8.2 plan:** `reviews/sprint-08-2-plan.md`  
**8.2B plan:** `reviews/sprint-08-2b-plan.md`

### Active phase
**Sprint 8.2B — Context Candidate Grouping** — 📋 **PLAN ONLY** (`reviews/sprint-08-2b-plan.md`). Do **not** write 8.2B code until that plan is explicitly approved.  
**Sprint 8.2A — Local high-confidence structured content typing:** **CLOSED / ACCEPTED** (2026-08-10). Visually semantic types deferred to **8.3A multimodal**.  
**Sprint 8.1 — Visual Understanding:** **CLOSED / ACCEPTED** (2026-08-10).  
**Sprint 8.0 — Intelligence Foundation Health:** **CLOSED / ACCEPTED** (2026-08-10).

### Intended outcome (end of Sprint 8)
```
New screenshot → local evidence → candidate group → multimodal context proposal
  → local Collection Resolver → reuse / create / Needs Review
```
Collection names are **dynamically inferred** (open-ended). Doc examples are illustrative only — not taxonomy seeds or exact benchmark strings.

### Status
**NOT ACCEPTED** (overall). Phases **8.0** + **8.1** + **8.2A CLOSED**. Remaining work is phased. Sprint 9 **not started**. Railway **paused**. Embeddings deferred to **8.7 conditional**.

### Definition of Done (Sprint 8 overall)
- [x] Phase **8.0** accepted (queue foundation health on device)
- [x] Phase **8.1** accepted (Vision Level 1 evidence quality on device)
- [x] Phase **8.2A** accepted (narrowed local structured content typing on device)
- [ ] Phases 8.2B→8.6 accepted in order (8.7 only if needed; 8.8 after quality)
- [ ] Physical-device organization quality passes Benchmark v1 targets (**naming judged by usefulness / equivalence — not exact string match to illustrative titles**)
- [ ] `source=user` preserved; thresholds 0.70 / 0.85 + corroboration unchanged
- [ ] Vision nouns never become Collection titles
- [ ] Dynamic Collection Invariant honored (no predefined taxonomy / seed names)

**Status:** **OPEN / NOT ACCEPTED** — active phase = **8.2B** (plan only; awaiting APPROVAL to code).

## Sprint 9 — Cleanup

### Goal
Ship reversible cleanup suggestions that reinforce trust.

### Deliverables
- Old suggestions (default 180 days)  
- Perceptual-hash duplicate grouping (from thumbnail pipeline)  
- Expired/time-bound using `eventEndDate` + facet heuristics  
- Dismiss / batch remove-from-app / batch delete Photos with dual confirmations  
- Cleanup tab + Home teaser wired to real suggestions  

### Dependencies
- Sprint 4 (thumbs/hash), 7–8 (facets/dates). **Blocked until Sprint 8 accepted.**

### Risks
- Aggressive duplicate false positives  
- Weak date detection → noisy expired list  

### Estimated complexity
**M** (3–4 days)

### Definition of Done
- [ ] No automatic deletes  
- [ ] Photos delete always confirms  
- [ ] Dismiss is reversible locally  
- [ ] Conservative duplicate grouping by default  

---

## Sprint 10 — Performance, Polish & Hardening

### Goal
Make the MVP feel premium, calm, and stable on realistic libraries.

### Deliverables
- Instruments pass: scrolling, import, OCR queue, search latency  
- Collage/cache tuning; import batching  
- Empty/error/offline/permission states completeness  
- Accessibility: VoiceOver labels, Dynamic Type, hit targets  
- Reduce Motion alternatives for hero transitions  
- Copy audit (memory language, not folders)  
- Privacy nutrition draft checklist  
- Bug bash against `11_ACCEPTANCE_CRITERIA.md`  

### Dependencies
- Sprints 4–9 feature-complete enough to polish  

### Risks
- Open-ended polish  
- Large-library surprises  

### Estimated complexity
**L** (4–6 days)

### Definition of Done
- [ ] Acceptance criteria checklist largely green  
- [ ] No severity-0/1 bugs in primary flows  
- [ ] Designer sign-off on visual/UX bar  
- [ ] Known issues list documented for TestFlight notes  

---

## Sprint 11 — TestFlight MVP

### Goal
Ship external builds safely with production gateway configuration.

### Deliverables
- Release signing, versioning, changelog  
- Production AI gateway + secrets not in client  
- Attest/rate limits enabled for TestFlight/prod  
- App Privacy questionnaire filled to match hybrid behavior  
- TestFlight group + internal script for PMF tasks (find memory, review Unassigned, cleanup)  
- Crash-free smoke on clean device  

### Dependencies
- Sprint 10; Apple Developer / ASC access; gateway prod  

### Risks
- Privacy label mismatch  
- Gateway abuse if Attest incomplete  
- Review guideline issues around Photos delete  

### Estimated complexity
**M** (2–4 days)

### Definition of Done
- [ ] Build live on TestFlight  
- [ ] External tester can complete onboarding → organize → search → cleanup  
- [ ] Docs acceptance criteria tagged shipped / waived with reason  
- [ ] No analytics/IAP/auth accidentally included  

---

## Parallel tracks (recommended)

| Track | Parallel with | Notes |
|-------|----------------|-------|
| AI gateway skeleton + prompt v1 | Sprints 5–7 | Unblocks Sprint 8 |
| Fixture “replay” organization JSON | Sprint 2–7 | Designer demos AI-like Home without cloud |
| pHash compute on thumbnail write | Sprint 4+ | Makes Sprint 9 cheaper |
| TestFlight ASC setup | Sprint 8–10 | Don’t leave to last afternoon |

---

## Critical review of this plan

### What works
- Designer feedback loop by end of **Sprint 2**  
- Docs-aligned: DB → Photos → OCR → Search → Manual → AI → Cleanup  
- Mock→real via protocols limits UI rework  
- AI failure doesn’t block a usable organizer (Sprint 7)

### Honest challenges / residual risks

1. **Sprint 2 is the schedule risk.** “Complete UI” expands. Mitigate: prioritize Home, Detail, Search, Onboarding, Cleanup happy paths; Settings secondary.  
2. **Sprint 8 (AI) is the product risk.** Quality of context titles makes or breaks the philosophy. Mitigate: stubbed demos + prompt eval set of 50–100 screenshots before polish.  
3. **Search before AI (Sprint 6) will feel incomplete** vs final magic. Acceptable: sell as “text find” then enrich.  
4. **Putting DB in Sprint 3 (before Photos)** slightly delays “real screenshots on screen” vs your original order — but saves a rewrite. Compromise: start Sprint 3 schema during Sprint 2; overlap 3→4.  
5. **11 sprints vs 10** looks longer; calendar can still fit if AI gateway is prepared in parallel and Sprint 2 is ruthlessly scoped.  
6. **Open questions OQ-1/2/3/6/12** should be locked before Sprint 7–8 to avoid resolver thrash.

### When your original order is better
If the only goal were **fastest real photo on screen**, Photos before SQLite wins by days — and costs a persistence rewrite. Given MVP scale (10k) and FTS, **DB-before-import is the better engineering trade.**

### Further compression option (if schedule-critical)
Merge Sprint 5+6 (OCR+Search) and 9+10 (Cleanup into Polish) → back to ~9–10 sprints, higher risk per sprint.

---

## Agreement checklist

- [ ] Accept revised 11-sprint order (or choose compression)  
- [ ] Lock remaining OQs needed for Sprint 7–8  
- [ ] Confirm GRDB (or alt) for SQLite  
- [ ] Confirm gateway hosting track starts by Sprint 5  

**Next step after agreement:** Execute **Sprint 0** only — still no feature code beyond foundation unless you say otherwise.
