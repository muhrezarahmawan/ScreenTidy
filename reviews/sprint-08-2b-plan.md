# Sprint 8.2B — Context Candidate Grouping — Plan (Revised)

**Status:** ✅ **CLOSED / ACCEPTED** — local precision-first candidate-grouping baseline (2026-08-10)  
**Completion:** `reviews/sprint-08-2b-completion-report.md`  
**Depends on:** Sprint **8.2A CLOSED / ACCEPTED** (`reviews/sprint-08-2a-completion-report.md`)  
**Canonical roadmap:** `docs/26_SPRINT_8_PHASED_INTELLIGENCE.md`  
**Parent 8.2 plan:** `reviews/sprint-08-2-plan.md`  
**Implementation approved:** 2026-08-10 (revised plan)  
**Physical eval:** Case A (chat) PASS · Case B (faces) FAIL / deferred · Case C under-signaled → R1 → R2a DEBUG verified  
**R2a:** ✅ IMPLEMENTED + physically verified  
**R2b:** ❌ **CANCELLED — not implemented**  
**Next:** Sprint **8.3A Multimodal Lab** (`reviews/sprint-08-3a-plan.md`) — APPROVED for implementation

**Role (locked):**  
**Local precision-first candidate grouping baseline** — not universal screenshot understanding.

**Out of scope (locked for 8.2B / post-accept freeze):**

- Collection names / CREATE / REUSE decisions  
- Multimodal LLM / Sprint 8.3A content understanding *(owned by 8.3A)*  
- Contextual Collection reasoning (8.3B+)  
- Resolver threshold changes  
- Lowering `admitFloor` without new signals  
- Further deterministic rules for WhatsApp/Instagram/LinkedIn/FB chrome, video calls, portraits, gameplay, NC layouts, arbitrary app UIs  
- Cloud face recognition / naming people  
- Embeddings (8.7)  
- Railway  
- Sprint 9  
- Full NER / graph ML / industrial clustering  

**Acceptance philosophy (locked):** **PRECISION FIRST.**  
False-positive grouping (unrelated shots admitted confidently) is **more damaging** than conservative fragmentation (a related shot left out). Multimodal 8.3+ can reason over imperfect but clean candidate sets; polluted sets corrupt context.

---

## Dynamic Collection Invariant (LOCKED)

Candidate groups are **taxonomy-neutral evidence bundles**.

They answer only:

> Which screenshots **probably belong together**?

They must **not** invent titles, force Collection membership, treat facets as folders, or treat Vision nouns as shared context.

Group identity = member set (+ diagnostics). **Never** a Collection ID.

---

## Goal

Produce **candidate groups** with:

- membership  
- group-health diagnostics (not mean-only)  
- signal provenance  
- per-member support for DEBUG  

**Stop before naming or Collection mutation.**

Illustrative (not a taxonomy seed):

```
A boarding_pass · B hotel_booking · C map · D trip chat
→ Candidate Group #1
   meanCohesion / weakestMemberSupport / memberSupport[]
STOP — no title, no CREATE
```

---

## Existing infrastructure (audit snapshot)

| Piece | Role today |
|-------|------------|
| `MultiSignalClusterer` | Seed-centered pairwise scorer + admit loop (hard-capped **8**) |
| `OrganizationBatchPlanner` | Thin wrapper |
| `OrganizationService` | Uses cluster for `batchMemberIDs` during organize |
| `candidate_cluster_id` / `cohesion` columns | Schema exists; not required for 8.2B proof |
| Visual Eval DEBUG | On-demand cluster around detail seed |
| FP neighbors | DEBUG visual similarity bands |
| Tests | Japan-trip-style cluster fixture; time-alone negative |

### Production vs DEBUG

| Path | Status |
|------|--------|
| Organize → `batchMemberIDs` | Production-used |
| Durable cluster lifecycle | **Defer** for 8.2B proof |
| Visual Eval clustering | DEBUG |
| Multimodal on groups | Not 8.2B |

---

## 1. Recommended clustering strategy

### Options compared

| Option | Idea | Pros | Cons for 8.2B |
|--------|------|------|----------------|
| **A** Seed-centered only (today) | Rank peers vs seed; take top-N | Simple; matches organize batch | Misses A↔B weak / B↔C strong chains; can admit several seed-friends that are incoherent with each other |
| **B** Pairwise group validation | After seed expansion, require each member pass group-level checks | Catches outliers | Needs a group model |
| **C** Full graph / connected components | Edge if score ≥ τ; take component | Natural multi-hop | Easy mega-clusters; harder DEBUG; more scope |
| **D** Seed expansion + group-level validation | Expand from seed with contextual edges; then validate / prune outliers | Smallest fix for seed mistakes | Still seed-initiated (OK for organize + DEBUG) |
| **E** Other | e.g. hierarchical agglomerative | Clean theory | Overkill for 8.2B |

### Recommendation: **D — seed expansion + group-level validation**

**Not** full graph clustering. **Not** embeddings.

**Algorithm (deterministic, bounded):**

1. **Contextual pairwise score** `S(i,j)` with policies below (entity tiers, Vision denylist, FP/time soft, facets positive/neutral only).  
2. **Expand:** from seed, admit candidates with `S(seed, c) ≥ admitFloor` **and** at least one **contextual support** family on that pair (defined below). Cap candidates considered (e.g. top K by score, K ≥ group max).  
3. **Bridge soften (optional, tiny):** if `S(seed, c)` is slightly below admit but `c` has **strong contextual** `S(c, m)` to an **already admitted** member `m`, allow provisional admit only when that bridge itself has contextual support — prevents pure seed-blindness without open graph flood. Limit bridge hops to **1**.  
4. **Validate group:** compute `memberSupport` for each member vs rest of group; **drop** members whose support falls below `outlierFloor` (precision-first prune). Recompute once.  
5. **Emit** `CandidateGroup` diagnostics. Cap final size at **8** (see §7).

This keeps organize’s seed-centered API while preventing “five friends of seed who don’t belong together” and allowing boarding↔hotel↔map style groups when contextual bridges exist.

---

## 2. Revised scoring / gating philosophy

### Contextual support (required for multi-member groups)

A pair (or a member’s link into a group) has **contextual support** if **at least one** of:

| Family | Qualifies when |
|--------|----------------|
| **High-tier entity overlap** | Shared booking/flight/ref/place/business-quality cues (see §3) |
| **Distinctive OCR overlap** | Shared non-stopword tokens after UI boilerplate removal, above a small threshold |
| **Strong facet same-type** | Shared **strong** facet ID |
| **Strong facet bridge** | Both have strong facets in an approved **bridge family** (travel / home) — **bonus only**, never penalty for different types |
| **Profile prior** | Shared profile title **and** another contextual family also present on the same pair/group |

**Does not qualify as contextual support alone:**

- time  
- feature print  
- generic Vision overlap  
- weak facets  
- profile + time  
- time + FP  
- time + generic Vision  

### Pairwise score roles

| Signal | Role |
|--------|------|
| High-tier entities | Strongest glue |
| Distinctive OCR tokens | Strong glue |
| Strong same-type facet | Modest positive |
| Strong cross-type bridge | Modest positive (carefully listed) |
| Different facets without bridge | **Neutral** (no bonus, **no penalty**) |
| Weak facet | Soft corroboration only; never sole admit |
| Distinctive Vision labels | Modest support |
| Generic Vision | **Zero** |
| Feature print | Soft corroboration / attach-only |
| Time | Soft corroboration only |
| Profile | Soft prior; requires independent contextual evidence |

### Facet difference ≠ conflict (**revised — remove penalty**)

**Removed from original plan:** “Conflicting strong facets (receipt vs boarding) → reduce score.”

Mixed strong types (`boarding_pass`, `hotel_booking`, `map`, `receipt`, `chat`) are **expected** in one real-world context.

| Situation | Action |
|-----------|--------|
| Same strong facet | Positive bonus |
| Bridge family (e.g. travel: boarding/hotel/map/reservation) | Modest positive bridge |
| Different facets, no bridge | **Neutral** |
| Same facet alone across shots | **Not** enough to merge (two unrelated hotels must not merge on `hotel_booking` alone — need entity/OCR contextual overlap) |

Only add a **true conflict** penalty later if we invent a defensible local contradiction rule. **Omit facet penalties in 8.2B.**

---

## 3. Entity-quality approach (no Japan/IKEA shortcuts)

**Remove:** hardcoded illustrative geography lists; Vision labels inside OCR entity helpers.

**Not building full NER.** Smallest deterministic extractors:

### Tier H — high (strong glue when shared)

- Booking / confirmation / reference patterns (`confirmation`, `booking ref`, `#` + alnum id length≥5, etc. — conservative regex)  
- Credible flight identifiers (reuse 8.2A-tight patterns, not `to 12`)  
- ≥2 shared credible IATA-style codes, or same validated route pair  
- Distinctive URL / domain (not `apple.com` / `google.com` boilerplate — small domain denylist)  
- Repeated uncommon multi-word proper phrases (capitalized runs length≥2 tokens, rarity: not in stopword list)

### Tier M — medium (helps with another family)

- Single distinctive place / property / business name token (length≥5, not city stopwords like `tokyo` alone as sole glue — prefer multi-token or with another cue)  
- Shared uncommon alphanumeric codes

### Tier L — low (ignore as glue)

- Year, clock, generic date fragments  
- Common prices / lone short numbers  
- UI chrome words  
- Generic geo words alone (`hotel`, `airport`, `city`, common country names used alone)

**Scoring:** only Tier H / M contribute to `ocr_entities`; Tier L never does. Shared Tier H can alone supply contextual support; Tier M needs a second family.

Vision labels stay in a **separate** `vision` channel — never mixed into entity extraction text.

---

## 4. Vision / OCR / FP / time policies

### OCR boilerplate

Small **grouping stopword set** (dozens, not hundreds): e.g. `settings`, `done`, `back`, `share`, `continue`, `cancel`, `search`, `today`, `home`, `ok`, `open`, `close`, `edit`, `delete`, `more`, `next`, `skip`, …

- Drop stopwords before Jaccard.  
- Prefer tokens length≥4 after stopword removal.  
- Optional: discount tokens that appear in &gt;N% of library only if cheap to compute in DEBUG; **not required** for v1 if stopword list + length gate suffice.

### Vision (explicit)

**Clustering denylist (zero contribution):**  
`document`, `adult`, `person`, `people`, `human`, `text`, `screenshot`, `screen`, `display`, `clothing`, `structure`, and other low-information nouns already aligned with Vision filter policy where applicable.

**Distinctive labels only** may add modest `vision` weight.

Vision never becomes a content-type classifier and never alone creates a group.

### Feature print

Answers: **visual similarity**, not shared context.

| Allowed | Forbidden |
|---------|-----------|
| Corroborate an already contextual pair | Create multi-member group from FP alone |
| Attach image-heavy / abstaining shot to an **already evidenced** group | FP + time ⇒ group |
| DEBUG neighbor discovery | Treat same-app chrome as context |

Negative test: same chrome / strong FP, unrelated OCR → stay separate.

### Time

Supporting only. Graduated bonuses may remain.

**Hard gate:** no multi-member group without **contextual support** somewhere in the validated member links (not merely on the seed’s raw admit list before prune).

---

## 5. Group-cohesion model (not mean-only)

**Remove:** cohesion = mean pairwise only as the sole health metric.

For members `M`, pairwise contextual scores `S(i,j)`:

| Metric | Definition | Use |
|--------|------------|-----|
| `meanCohesion` | Mean of `S(i,j)` over pairs | Overall |
| `weakestPairSupport` | Min `S(i,j)` among pairs that were used as support edges (or min over all pairs in group) | Spot fragile links |
| `memberSupport[m]` | Aggregate / mean of `S(m, other)` for others in group (prefer mean of top contextual links) | “Why is m here?” / outlier |
| `weakestMemberSupport` | Min over `memberSupport[m]` | Outlier detection |
| `supportedEdgeCount` | Count of pairs with contextual support | Density |

**Outlier rule (precision-first):** if `memberSupport[m] < outlierFloor`, drop `m` (except seed, or demote seed-only singleton). Prefer dropping one bad member over keeping a pretty mean.

DEBUG must surface these so humans see: “group OK overall, but X looks wrong.”

---

## 6. CandidateGroup representation

```text
CandidateGroup {
  id: String                         // hash of sorted memberIDs — NOT a Collection ID
  memberIDs: [ScreenshotMemoryID]

  meanCohesion: Double
  weakestMemberSupport: Double
  weakestPairSupport: Double
  supportedEdgeCount: Int

  signalBreakdown: [String: Double]  // aggregated positive parts

  memberSupport: [{
    id: ScreenshotMemoryID
    support: Double
    topSignals: [String: Double]     // why this member
    strongFacets: [String]           // evidence only
  }]

  flags: [String]                    // e.g. pruned_outlier, bridge_admit,
                                     // vision_denylist_applied, fp_attach_only
}
```

**No titles. No Collection decisions. No multimodal fields.**

---

## 7. Group size recommendation

| Fact | Detail |
|------|--------|
| Why 8 today | `ResolverPolicy.maxBatchSize = 8` — cloud/multimodal batch ceiling + local safety cap (`MultiSignalClusterer` also hard-clamps to 8) |
| Risk | Real contexts with &gt;8 shots **fragment** into multiple candidate groups |
| 8.3 later | Can retrieve multiple candidate groups / expand representatives; not solved in 8.2B |

**8.2B recommendation:**

- **Keep final candidate-group max = 8** (align with organize/multimodal batch ceiling).  
- Treat 8 as an **implementation / payload safety cap**, not a claim that contexts are ≤8.  
- Optionally make **DEBUG retrieval pool** larger (e.g. consider top 20 scored peers) while still emitting groups of ≤8 after validation — **separate candidate retrieval size from final group size**.  
- Do not raise production max without an explicit later decision.

---

## 8. Persistence decision (**locked for 8.2B**)

**Choose A — on-demand DEBUG (+ existing organize ephemeral batch).**

- Prove quality with DEBUG/on-demand evaluation first.  
- Do **not** build durable candidate-group lifecycle in 8.2B.  
- Existing `candidate_cluster_*` columns may remain unused or lightly written by organize as today — **no new persistence product**.  
- Compatible with organize: `batchMemberIDs` stay ephemeral per organize call.

**Defer B** (durable group persistence / library-wide recompute jobs) until after 8.2B ACCEPT if still needed.

---

## 9. DEBUG tooling

Extend Visual Intelligence (or Candidate Groups DEBUG):

1. Seed → computed `CandidateGroup` with thumbnails.  
2. `meanCohesion`, `weakestMemberSupport`, `supportedEdgeCount`.  
3. Per-member support + topSignals (“why is THIS here?”).  
4. Pairwise parts table for seed↔member and member↔member on demand.  
5. Eval harness UI or documented procedure for positive/distractor sets (see §10).  
6. Banner: **Candidate group — not a Collection.**  
7. On-demand recompute only (no Collection mutation).

---

## 10. Evaluation-set methodology (tiny, not 8.5)

Before ACCEPT, manually define **≥2–3** real-library mini-sets:

```text
POSITIVE expected members: A B C D
DISTRACTORS: E F G
```

No Collection names. Expected answer = membership / cohesion / outlier flags only.

For each set, record:

- expected recovered  
- distractors admitted (should be ~0)  
- missing expected (OK if precision preserved)  
- outliers flagged/pruned  
- provenance readable  

Do not tune thresholds to a single set.

---

## 11. Metrics (diagnostic)

| Metric | Definition |
|--------|------------|
| Member recall | \|recovered ∩ expected\| / \|expected\| |
| Group precision | \|admitted ∩ expected\| / \|admitted\| (excl. seed if needed) |
| Distractor FP rate | \|admitted ∩ distractors\| / \|distractors\| |
| Singleton correctness | Unrelated seeds stay singleton or non-merging |
| Outlier catch | Bad member dropped or `weakestMemberSupport` flags it |

**Optimize for high precision / near-zero distractor FP**; accept imperfect recall.

---

## 12. Physical-device matrix (required negatives)

| ID | Scenario | Expect |
|----|----------|--------|
| A | Same time, unrelated content | Stay separate |
| B | Same generic Vision `document` | Stay separate |
| C | Same generic Vision `adult` | Stay separate |
| D | Strong FP / same app chrome, unrelated context | Stay separate |
| E | Different appearance, shared high-tier entities | May group |
| F | Mixed strong facets boarding+hotel+map+chat with contextual support | May group |
| G | Same facet `hotel_booking`, different real contexts | Must **not** merge on facet alone |
| H | Image-heavy weak OCR | Attach only if corroborated by evidenced group |
| I | Profile similarity without independent context | Must not force membership |
| J | Seed-friends incoherent with each other | Validate/prune; no mean-washed bad member |

---

## 13. Revised acceptance criteria (precision-first)

| # | Criterion |
|---|-----------|
| G1 | On positive eval sets, group precision high; distractor FP ≈ 0 preferred over perfect recall |
| G2 | Missing a related member is acceptable; admitting a distractor is a **fail** |
| G3 | Time alone never creates a multi-member group |
| G4 | Time+FP, time+generic Vision, profile+time insufficient without contextual support |
| G5 | Generic Vision overlap contributes ~0; does not form groups |
| G6 | FP alone does not form contextual groups; chrome look-alikes stay apart |
| G7 | Mixed strong facets allowed when contextual evidence supports; **no** facet-difference penalty |
| G8 | Same facet alone does not merge different real-world contexts |
| G9 | Weak facets / profile hints never sole admit |
| G10 | Group diagnostics expose mean + weakest member + per-member support; outliers detectable |
| G11 | Seed expansion + validation prevents incoherent seed-friend bags |
| G12 | DEBUG explains membership; no Collection naming/mutation; Dynamic Collection Invariant held |

**Non-goals:** naming, multimodal types, resolver CREATE/REUSE, embeddings, durable group DB product.

---

## 14. Exact files expected to change (if approved)

| File | Change |
|------|--------|
| `ScreenTidy/Data/Organization/MultiSignalClusterer.swift` | Primary: strategy D, contextual gates, entity tiers, Vision denylist, FP/time soft, facet positive/neutral, group diagnostics, prune outliers; remove Japan/IKEA helper & Vision-in-OCR bridge; remove facet conflict penalty / image_only soft glue |
| `ScreenTidy/Data/Organization/OrganizationBatchPlanner.swift` | Pass richer `CandidateGroup` if needed |
| `ScreenTidy/Data/Organization/OrganizationService.swift` | Consume validated member IDs only; no naming / threshold changes |
| `ScreenTidy/Domain/Models/OrganizationModels.swift` | Snapshot / group DTO if required |
| `ScreenTidy/Data/Persistence/GRDBMemoryRepository.swift` | On-demand DEBUG group build only (no new persistence product) |
| `ScreenTidy/Features/Settings/VisualIntelligenceDebugInspectorView.swift` | Group health + memberSupport DEBUG |
| `ScreenTidyTests/…` | Fixtures for matrix A–J + precision-first cases |
| Docs | completion report after ACCEPT |

**Do not touch:** Railway, embeddings, CollectionResolver thresholds, ScreenshotFacetDeriver vocabulary, Lab multimodal.

---

## 15. Removed / superseded from prior plan draft

| Prior item | Disposition |
|------------|-------------|
| Facet conflict penalty (receipt vs boarding) | **Removed** — difference is neutral |
| Cohesion = mean only | **Superseded** — add weakest member/pair + memberSupport |
| Seed-centered scoring as sufficient | **Superseded** — seed expansion + group validation |
| Hardcoded Japan/IKEA entity cues | **Removed** |
| Vision labels mixed into geography/OCR helpers | **Removed** |
| Undecided persistence A vs B | **Decided: A on-demand**; durable lifecycle deferred |
| image_only soft facet glue | **Removed** (obsolete post-8.2A) |
| “Raise coverage” framing | **Replaced** with precision-first |
| Full connected-component / graph clustering | **Not chosen** for 8.2B |
| Naive proper-noun / any-number entity glue | **Rejected** — use quality tiers |

---

## Working agreement

1. This revision is **PLAN ONLY**.  
2. Implement 8.2B only after explicit **APPROVE Sprint 8.2B plan** (this revision).  
3. After implementation: tests → tiny eval sets → physical matrix → **STOP** for ACCEPT.  
4. Do not start 8.3A/8.3B/9 from this work.

---

## Status summary

| Phase | Status |
|-------|--------|
| 8.0 | ✅ CLOSED |
| 8.1 | ✅ CLOSED |
| **8.2A** | ✅ CLOSED / ACCEPTED |
| **8.2B** | 🔵 ACTIVE — **NOT ACCEPTED** (physical eval 2026-08-10; DEBUG retrieval OK; capability gaps below) |
| 8.3A+ | ⛔ NOT STARTED |
| 9 | ⛔ NOT STARTED |

---

## 16. Physical evaluation (2026-08-10) — NOT ACCEPTED

**DEBUG retrieval fix: ACCEPTED as infrastructure.** Peer pools score (~198 peers observed). Do not revisit the empty-pool bug.

### Case A — WhatsApp / chat — PASS

Observed (example): peers scored 198 · group size 8 · mean cohesion ~0.475 · weakest member ~0.424 · weakest pair ~0.330 · contextual edges 25 · members genuinely related chat screenshots.

**Why it works today:** strong dialogue OCR, shared app/chrome tokens, distinctive token/entity overlap, and often the `chat` strong facet — enough for contextual support **and** scores ≥ `admitFloor`. Confirms strategy D + multi-signal scoring can produce useful groups when evidence is dense.

### Case B — people / faces — FAIL (capability gap)

Person photos do not group with other photos of the **same** person across pose/background/clothing/crop/lighting.

- Generic Vision (`adult`, `eyeglasses`, `clothing`, …) describes objects, not identity.  
- Must **not** become contextual glue.  
- Whole-image Feature Print is insufficient for same-person matching under appearance change.

**Root cause:** missing **person-similarity** signal. Not fixable by lowering `admitFloor`.

### Case C — source / platform / content-family — FAIL (capability gap)

Need relationships such as:

| Level 1 source/type (examples) | Level 2 family | Level 3 context (later) |
|--------------------------------|----------------|-------------------------|
| `instagram_post`, `linkedin_post`, `facebook_post` | `social_media` | e.g. Qatar Airways job search |
| `email` / Gmail | `email` | same thread / campaign |
| `whatsapp_chat`, iMessage, Messenger | `messaging` | conversation with a person |
| resident ID / passport | `identity_document` | — |
| product / shopping page | `commerce` | apartment furnishing |
| maps / navigation | `navigation` | Japan trip |
| boarding / hotel | `travel` | Japan trip |

Today FacetDeriver often emits coarse `social_post` / `chat` / `product_page` / `map`, and clustering still leans on OCR/entity overlap. Same source/family alone must **not** force a Context Collection — but it should be usable **evidence** for candidate formation when corroborated.

**Physical near-miss pattern:** totals ~0.150 with `facet_bridge_home` +0.12 and `feature_print` +0.03. **Do not lower `admitFloor` to catch these** — that would admit weak FP/facet pairs and damage precision. Missing **semantic / source / person** signals, not threshold calibration.

### Locked interpretation

| Observation | Decision |
|-------------|----------|
| WhatsApp works | Preserve current chat/OCR path; regression-lock it |
| Faces fail | Capability gap → investigate on-device person similarity; **defer implementation** |
| Platform/family fails | Capability gap → propose bounded evidence model; **plan revision before code** |
| Scores ~0.15 with only home-bridge + FP | **Do not** lower 0.32 |

---

## 17. Proposed architecture revision (PLAN ONLY — awaiting approval)

### 17.1 Separate evidence layers (must not be conflated)

| Layer | Answers | Examples | May alone admit multi-member group? |
|-------|---------|----------|-------------------------------------|
| **Visual similarity** | Look alike as whole frames? | Feature print | **No** |
| **Same person** | Same visual face/person? | Future face crop + local embedding (not shipped) | Only with strict corroboration later |
| **Source / platform** | Which app/UI chrome? | `instagram`, `linkedin`, `gmail`, `whatsapp` | **No** alone |
| **Content type** | What kind of screen? | `instagram_post`, `email`, `boarding_pass` | **No** alone (keep “same type ≠ same context”) |
| **Content family** | Broad class | `social_media`, `messaging`, `travel`, `commerce` | **No** alone; soft bridge like travel today |
| **Semantic / context cues** | Same real-world episode? | entities, distinctive OCR, thread ids, company names | Primary glue (as today) |
| **Context Collection identity** | What to name / CREATE | 8.3+ | **Out of 8.2B** |

**Dynamic Collection Invariant unchanged:** these fields are evidence only — never Collection titles or taxonomy folders.

### 17.2 Source / type / family model

Prefer a **small dedicated evidence struct** (names illustrative):

```
sourcePlatform?: instagram | linkedin | facebook | gmail | whatsapp | …
contentType?:    instagram_post | linkedin_post | email | whatsapp_chat | identity_document | …
contentFamily?:  social_media | messaging | email | identity_document | travel | commerce | navigation | …
```

**Derivation:** extend local OCR/UI chrome detectors (reuse FacetDeriver platform phrases where helpful) — emit **structured evidence**, not only a collapsed `social_post` facet.

**FacetDeriver relationship:**

- Keep Level 2A facets for typing where they already work (`boarding_pass`, `hotel_booking`, `chat`, `map`, …).  
- **Do not** overload facets as Collection names.  
- Add **sourcePlatform / contentType / contentFamily** as parallel evidence (either new deriver output fields or a thin `ScreenshotSourceDeriver`) so Instagram vs LinkedIn are distinguishable while both map to `social_media`.

### 17.3 Scoring / gating (precision-first)

Keep `admitFloor = 0.32` and current “soft signals alone never admit” rule.

| Pair situation | Score role | Contextual support? |
|----------------|------------|---------------------|
| Shared **high-tier entity / distinctive OCR** | Strong (unchanged) | Yes |
| Same **contentType** alone (two random Instagram posts) | Modest positive only | **No** — prevents mega social bags |
| Same **contentFamily** alone | Soft / bridge-like | **No** alone |
| Same platform/type **+** shared entity/OCR/topic phrase | Stronger | **Yes** (corroborated source) |
| Cross-platform same family (IG + LinkedIn) **+** shared company/topic entity | Modest + contextual | **Yes** when entity/OCR corroborates |
| Cross-platform same family, unrelated OCR | Soft only | **No** |
| Same `hotel_booking` facet alone | Modest (unchanged) | **No** (unchanged) |
| Travel / home facet bridge | Modest (unchanged) | Yes as today for listed bridges |
| Generic Vision person/adult | **Zero** glue (unchanged) | **No** |
| Feature print | Soft only (unchanged) | **No** |
| Future same-person similarity | Separate channel | Never alone without corroboration policy |

**Reaffirm:** “same facet alone must not merge unrelated contexts” stays. Extend the same precision rule to **same source/type/family alone**.

WhatsApp path remains: dense OCR + messaging type → existing admit behavior preserved.

### 17.4 Same-person feasibility (Apple / on-device)

| Capability | Status |
|------------|--------|
| `VNDetectFaceRectangles` / landmarks | Detect faces; quality/pose — **not** identity |
| `VNFaceObservation` UUID | Not stable across images |
| Public face embedding / faceprint compare API | **Not available** in Vision |
| `VNGenerateImageFeaturePrintRequest` | Whole-image similarity; fails Case B |
| Photos “People” album APIs | **Not** a public third-party face graph API |
| Custom on-device Core ML face embedding on face crops | Possible later; privacy review; model size; false matches |

**Privacy stance (locked for any future work):** on-device only; similarity for grouping; **no names**; no cloud face recognition; no identity graph productization in 8.2B.

**Recommendation:** **defer same-person** out of 8.2B (candidate: dedicated later sprint or 8.3+ after multimodal). Do not pretend FP or `adult` labels solve Case B.

### 17.5 Scope recommendation

| Track | Action |
|-------|--------|
| DEBUG retrieval + rejected diagnostics | Done — keep |
| Threshold tuning (`0.32`) | **Blocked** until new signals exist |
| Source / type / family evidence + gated scoring | **Propose as 8.2B revision** (or labeled **8.2B-R1**) — smallest principled fix for Case C |
| Same-person similarity | **Defer** — capability investigation only in this plan |
| Embeddings / full graph / multimodal / Collections | Still blocked |

**Verdict for approval:** revise **8.2B** for source/type/family evidence + DEBUG; **defer** face/person similarity; **do not** lower admitFloor; **preserve** WhatsApp.

### 17.6 DEBUG diagnostics (for next physical pass)

Per seed / rejected peer, expose:

- `sourcePlatform`, `contentType`, `contentFamily` (seed + candidate)  
- whether pair matched on platform / type / family  
- whether corroboration (entity/OCR) fired  
- rejection reason including `source_alone_insufficient` / `family_alone_insufficient` when applicable  
- keep existing score parts + singleton reasons  

Still on-demand; still “CANDIDATE GROUP — NOT A COLLECTION”.

### 17.7 Regression matrix (automated, when implementing)

| ID | Scenario | Expect |
|----|----------|--------|
| A | Same person, different background | **No** group until person signal exists; must not group via `adult` |
| B | Different people, similar composition | Must **not** group |
| C | Multiple Instagram posts, unrelated topics | Must **not** multi-member on platform alone |
| D | Instagram + LinkedIn, same company/topic | May group when entity/OCR corroborates |
| E | Instagram + LinkedIn, unrelated | Must **not** group |
| F | Multiple emails same thread | May group (shared refs/subject/entities) |
| G | Unrelated emails | Must **not** group |
| H | Resident ID vs unrelated document | Must **not** group on “document” Vision |
| I | WhatsApp same conversation | **Must** continue to group (lock Case A) |
| J | Unrelated WhatsApp conversations | Must **not** merge solely on `whatsapp`/`chat` |

### 17.8 Files that would change (if revision approved — not now)

| File | Likely change |
|------|----------------|
| New or `ScreenshotFacetDeriver.swift` / source deriver | Emit platform / type / family evidence |
| Persistence / memory models | Store or DEBUG-recompute evidence fields |
| `MultiSignalClusterer.swift` | New soft channels + corroboration gates (thresholds unchanged unless evidence justifies) |
| Visual Eval DEBUG DTOs + inspector | Show platform/type/family on seed & rejected |
| Tests | Matrix A–J |
| This plan + completion notes | After ACCEPT |

**Do not touch yet:** admitFloor, Collection resolver, multimodal, Railway, embeddings, naming.

### 17.9 Risks / false positives

| Risk | Mitigation |
|------|------------|
| All Instagram → one mega-group | Same type/family alone ≠ contextual support |
| All chats merge | Require conversation-level OCR/entity corroboration (preserve I vs J) |
| `adult` becomes person glue | Explicit denylist; zero weight |
| Lowering 0.32 for 0.15 near-misses | **Forbidden** in this revision |
| Treating family as Collection name | Invariant + DEBUG banner |
| Premature face ML | Defer; privacy review first |

### 17.10 Decision asked

**Approve plan revision direction:**

1. **8.2B-R1** — implement sourcePlatform / contentType / contentFamily evidence + gated scoring + DEBUG (no threshold cut; lock WhatsApp).  
2. **Defer** same-person to a later sprint after Apple/on-device options are chosen.  
3. **STOP** — no code until explicit approval.

---

## 18. Physical verification of 8.2B-R1 — FAILED (2026-08-10 evening)

**8.2B remains NOT ACCEPTED.** R1 shipped; physical verification failed. **8.2B-R2 = investigation/plan only (this section).** No code until explicit R2 approval.

### 18.1 Observed physical failures

| Case | Observed | Problem |
|------|----------|---------|
| WhatsApp chat (obvious UI: wallpaper, bubbles, timestamps, quotes) | `sourcePlatform = unknown` | Platform detection requires literal OCR chrome (`whatsapp`, `voice message`, `tap to call`) |
| Candidate groups size 7–8 | Need to verify genuine relatedness | Risk of correlated weak-signal accumulation |
| Lock screen + Gmail notification | platform/type/family all `unknown` — and must **not** become “this is a Gmail screen” | Missing **surface/container** vs **embedded content** distinction; also no safe partial evidence model |

Constraints locked for R2 planning: no `admitFloor` change; no weight inflation; no screenshot-specific keyword hacks; no 8.3A/9; same-person deferred.

---

### 18.2 Root cause A — WhatsApp → `sourcePlatform=unknown`

**Exact R1 platform path** (`ScreenshotSourceDeriver.detectPlatform`):

Needles for WhatsApp: `whatsapp` | `voice message` | `tap to call` only.  
No wallpaper/bubble/geometry; no use of FacetDeriver chat structure; no Vision assist for messaging UI.

**Typical real WhatsApp screenshot OCR:**

- Message bodies, timestamps, quoted reply text  
- Often **no** literal string `"WhatsApp"` in the crop  
- Delivery labels (`Delivered` / `Read`) may appear — **not** in R1 WhatsApp needle list (intentionally avoided earlier for false iMessage positives)

**Trace (platform):**

```
OCR contains "whatsapp"? → NO
OCR contains "voice message" / "tap to call"? → often NO
→ sourcePlatform = unknown
platform evidence = []
```

**Type/family path (coupled today):**

1. If Level 2A `chat` strong facet exists → R1 maps `contentType=chat`, `contentFamily=messaging` (platform stays unknown).  
2. If FacetDeriver also abstains (sparse lines, poor adjacency, feed-guard) → R1 has **no structural chat fallback** when platform is unknown → type/family also `unknown`.

**Gap:** R1 treats platform as a prerequisite for messaging typing in the platform-led branch, and does not separately expose “chat structure confidence” when platform is abstained. Architecture *can* recognize messaging structurally (FacetDeriver already does dialogue adjacency / turns) — R1 simply does not wire that into type/family independently of platform chrome, and never upgrades platform from structure alone (correct for platform; wrong if type/family also collapse).

**Abstention reason (implicit):** no OCR platform needle hit; no separate DEBUG abstention string today.

---

### 18.3 Root cause B — platform vs type vs surface

R1 stores one flat triple and one blended confidence. That conflates:

| Concept | Should answer | R1 today |
|---------|---------------|----------|
| **Platform** | Which app chrome? | OCR name needles only |
| **Content type / family** | What kind of content? | Facet map or platform-led; weak without either |
| **Surface / container** | What is the screenshot *of*? (app screen vs lock screen vs NC) | **Missing** |

**Lock screen + Gmail notification:**

- Correct: surface ≈ lock screen / notification center; embedded evidence may mention Gmail.  
- Incorrect: `sourcePlatform=gmail` + `contentType=email` for the whole shot.  
- R1 currently often returns all-unknown (no `gmail` in OCR, no email structure on lock UI) — safer than false Gmail, but DEBUG cannot show “embedded gmail cue / surface=lock_screen”.

**Principle for R2:**  
`platform=unknown` is acceptable while `type=chat` / `family=messaging` can still be known.  
Surface/container must be first-class so embedded notifications cannot redefine the screenshot identity.

---

### 18.4 Root cause C — 7–8 member groups / correlated evidence

R1 adds modest weights but **adds them on top of correlated channels**:

Example: two strong `chat` peers with shared dialogue OCR:

| Signal | Typical contribution | Independence |
|--------|----------------------|--------------|
| `facets` (same `chat`) | up to ~0.08–0.14 | type evidence |
| `content_type` | +0.05 | **same fact as facet** |
| `content_family` | +0.04 | **same fact as type** |
| `ocr_tokens` / entities | variable | often real context |
| `time` | soft | soft |
| `source_with_context` etc. | family tags only | after OCR already passed |

Same-type facet + content_type + content_family can **triple-count “it’s chat”** while OCR supplies the only independent contextual gate. That does not lower admitFloor, but can push borderline pairs over 0.32 and help seed-expand fill toward max size 8.

DEBUG today shows rejected peers well; **admitted members lack per-admission score + independence audit**, so physical 7–8 groups cannot be judged cleanly.

---

### 18.5 Proposed R2 architecture (PLAN ONLY)

#### Evidence layers (orthogonal)

```
platform:     { id, confidence, evidence[] }   // may be unknown
type:         { id, confidence, evidence[] }   // may be known without platform
family:       { id, confidence, evidence[] }   // derived from type primarily
surface:      { id, confidence, evidence[] }   // lock_screen | notification_center | app_screen | unknown
embeddedHints: [{ platform?, type?, evidence[] }]  // optional; never overrides surface alone
```

Still **not** Collection identity.

#### Derivation rules (precision-first)

1. **Platform** — only platform-specific chrome / distinctive non-generic cues; abstain freely. Structure alone never forces `whatsapp` vs `imessage`.  
2. **Type/family** — may use FacetDeriver chat structure / dialogue adjacency **without** platform name; emit `chat`/`messaging` with structure evidence.  
3. **Surface** — lock/NC patterns (time+date status, notification stacking, “Notification Center” chrome, wallpaper+clock layout cues) vs full app chrome.  
4. **Embedded content** — e.g. Gmail notification text recorded as embedded hint when surface is lock/NC; does **not** set screenshot `sourcePlatform=gmail` or `contentType=email` unless surface is app_screen email.

#### Scoring / gating (no admitFloor change; no weight increase)

1. **Anti double-count:** treat facet / content_type / content_family as one **semantic-type channel** for scoring (max contribution capped as a single family), or only score the strongest of the three — not all three stacked.  
2. Keep: type/family/platform alone ≠ contextual support.  
3. Prefer independent OCR/entity for admit; type/family only corroborate.  
4. Optional DEBUG-only: `correlated_type_stack` flag when facet+type+family all fire.

Do **not** raise source/type/family weights.

#### DEBUG (do this before / with behavior change)

Seed:

```
SOURCE   platform / confidence / evidence
TYPE     type / confidence / evidence
FAMILY   family / confidence / evidence
SURFACE  surface / evidence
EMBEDDED hints (if any)
```

Per admitted + rejected peer:

```
total score
parts[] with keys
which family supplied contextual support
admissionReason / rejectionReason
correlatedChannels[] (e.g. facet≡type≡family)
```

---

### 18.6 R2 regression fixtures (from physical failures)

| ID | Fixture | Expect |
|----|---------|--------|
| R2-1 | WhatsApp chat **without** literal “WhatsApp” OCR | `type=chat`, `family=messaging`; `platform=whatsapp` only if platform-specific evidence strong, else `platform=unknown` OK |
| R2-2 | Generic chat UI (no platform chrome) | chat/messaging allowed; platform **unknown** |
| R2-3 | iOS lock screen + Gmail notification | surface ≠ gmail app; do **not** classify whole shot as Gmail/email solely from embedded notification |
| R2-4 | Map/navigation with strong cues | map/navigation; platform unknown unless maps chrome present |
| R2-5 | Unrelated shots sharing weak type/family/visual | singleton / no mega-group |
| R2-6 | WhatsApp same conversation (positive) | still groups with independent contextual OCR/entity |
| R2-7 | Unrelated WhatsApp / messaging (negative) | stay separate on messaging alone |
| R2-8 | Correlated facet+type+family stack | score must not admit on type-stack alone; DEBUG shows correlation |

Preserve existing 8.2B / R1 negatives (adult Vision, Instagram alone, etc.).

---

### 18.7 Files that would change (if R2 approved later)

| File | Likely change |
|------|----------------|
| `ScreenshotSourceEvidence.swift` | Split platform/type/family/surface/embedded; per-field confidence + evidence |
| `ScreenshotFacetDeriver.swift` | Possibly share chat-structure helpers (read-only reuse) — no Collection taxonomy |
| `MultiSignalClusterer.swift` | Anti double-count for type channel; richer admission diagnostics |
| Visual Eval DEBUG DTOs + inspector | Layered SOURCE/TYPE/FAMILY/SURFACE + per-member admit audit |
| Tests | R2-1…R2-8 |
| This plan | mark R2 implemented after ship |

**Do not touch:** admitFloor, Collection resolver, multimodal, face/person, Railway.

---

### 18.8 Risks

| Risk | Mitigation |
|------|------------|
| Structural chat over-fires on NC/feeds | Reuse FacetDeriver feed/NC guards; surface=notification_center |
| Lock screen under-classified forever | Explicit surface + embedded hints in DEBUG first |
| Anti double-count reduces legitimate WhatsApp groups | Keep OCR/entity path; lock R2-6 positive |
| Pixel/template matching | Out of scope — structure + OCR only |

---

### 18.9 Recommendation

1. **Do not ACCEPT 8.2B.**  
2. Approve **8.2B-R2** in two phases if desired:  
   - **R2a (DEBUG-first):** layered evidence + per-admit peer audit (no scoring change) so next physical pass is interpretable.  
   - **R2b (behavior):** independent type/family without platform; surface vs embedded; anti double-count on facet/type/family.  
3. Keep `admitFloor=0.32`; do not inflate R1 weights.  
4. Same-person remains deferred.  
5. **STOP** — no code until explicit **APPROVE 8.2B-R2**.

---

## Working agreement

1. Implementation of 8.2B-R1 only after explicit **APPROVE**.  
2. No admitFloor change without new-signal evidence.  
3. Do not start 8.3A / 9 from this work without a separate plan approval.  
4. Same-person remains investigation-only until a dedicated approval.  
5. **8.2B-R1 physical FAIL → R2 plan (§18).**  
6. **8.2B-R2a IMPLEMENTED** + physically verified.  
7. **R2b CANCELLED** — no further deterministic chrome / type expansion.  
8. **Local heuristic layer FROZEN** at Level 1 / 2A / 2B baseline roles (see §19).  
9. **8.2B ACCEPTED** as local candidate-grouping baseline (`reviews/sprint-08-2b-completion-report.md`).  
10. Visually semantic understanding → **Sprint 8.3A** (APPROVED / implementing).

---

## 19. Physical boundary + proposed LOCAL BASELINE acceptance (2026-08-10 evening)

### 19.1 Physical findings (R2a)

| Case | Result | Implication |
|------|--------|-------------|
| Lock screen + Gmail notification | `surface=lock_screen`; platform/type/family unknown | Surface vs embedded separation works; whole-shot Gmail avoided |
| Obvious WhatsApp UI (no app-name OCR) | `app_screen` + platform/type/family **unknown** | Local rules cannot replace visual semantics |
| Social / video call / portrait / gameplay / NC / weak-OCR UIs | Under-signaled or abstain | Belongs to multimodal |
| High-signal WhatsApp conversation group | peers 198 · size 8 · cohesion ~0.475 · weakest ~0.424 · edges 25 | Local grouping **works when evidence is strong** |
| Travel / boarding / hotel with strong OCR | Reasonable | Level 2A structured facets remain valuable |

### 19.2 Architecture freeze

Stop expanding deterministic OCR/layout rules into a universal screenshot-understanding engine.

**Local keeps:** Level 1 (OCR, Vision labels, FP, metadata) · Level 2A high-confidence structured facets + abstain · Level 2B precision-first candidate grouping (OCR/entities/facets/time/FP/profile + source/type/family when available).

**Local must not add rules for:** WhatsApp/IG/LinkedIn/FB visual chrome, video calls, portraits, gameplay, arbitrary NC/app UIs.

**Multimodal owns:** visually semantic content understanding (8.3A) and later contextual Collection reasoning (8.3B+).

### 19.3 R2b

**CANCELLED.** Do not implement independent structural type inference expansion, anti–double-count scoring changes, or further chrome heuristics as an 8.2B behavior sprint. R2a DEBUG instrumentation remains valuable and stays.

### 19.4 Acceptance (formalized 2026-08-10)

**ACCEPTED** as ScreenTidy’s **local precision-first candidate-grouping baseline**.  
See `reviews/sprint-08-2b-completion-report.md`.

**R2b remains CANCELLED.** Do not reopen 8.2B for deterministic chrome expansion.
