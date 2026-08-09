# Research Proposal — Apple Vision Visual Signals for ScreenTidy

**Status:** **APPROVED** as part of Architecture **C** (Multi-Signal Contextual Intelligence)  
**Date:** 2026-08-09  
**Sprint 8:** remains **NOT ACCEPTED** — Vision is **P1** after **P0** hosted multimodal smoke  
**Sprint 9:** **not started**  
**Implementation:** Do **not** start until P0 physical-device smoke passes and P1 is explicitly approved  

Related:
- `reviews/intelligence-architecture-multisignal-proposal.md` (**canonical** Architecture C)
- `docs/07_AI_PIPELINE.md`
- `docs/08_PRIVACY_SECURITY.md`
- `docs/24_SPRINT_8_COLLECTION_RESOLVER.md`
- Apple: [VNClassifyImageRequest](https://developer.apple.com/documentation/vision/vnclassifyimagerequest), [ClassifyImageRequest](https://developer.apple.com/documentation/vision/classifyimagerequest), [VNGenerateImageFeaturePrintRequest](https://developer.apple.com/documentation/vision/vngenerateimagefeatureprintrequest)

---

## Executive verdict

**Apple Vision strengthens ScreenTidy as an on-device visual-evidence layer.** Labels must **never** become Collection names. Vision is **P1** within approved Architecture C — after hosted multimodal (**P0**) works on device.

Recommended overall architecture: **C — Hybrid** (see intelligence proposal).

Wrong filing is worse than Needs Review. Keep assign ≥ **0.70**, create ≥ **0.85** + corroboration.

---

## 1. What Apple’s APIs actually provide

### 1.1 `VNClassifyImageRequest` (legacy ObjC API — available today)

From Apple’s Vision headers (iPhoneOS 26.5 SDK) and docs:

| Property | Detail |
|----------|--------|
| Availability | iOS **13+** |
| Purpose | General-purpose **image classification** → `[VNClassificationObservation]` |
| Observation | `identifier: String` + `confidence: Float` (0…1) |
| Taxonomy | **~1,303 identifiers** (Revision 1); Revision 2 keeps the **same taxonomy** with better accuracy / latency / memory |
| Revisions | `Revision1` (iOS 13), `Revision2` (iOS **17+**) |
| Identifier list | `supportedIdentifiersAndReturnError:` (iOS 15+) — query at runtime |
| Filtering aids | `hasMinimumPrecision(_:forRecall:)` / `hasMinimumRecall(_:forPrecision:)` on observations |

Apple documents this as a **built-in classifier** (no custom Core ML model required). Results describe **objects / scenes / animals / common visual categories**, not ScreenTidy “contexts.”

Practical note from Apple sample guidance and field reports: the request can emit **hundreds of low-confidence labels**. Always filter (confidence and/or precision–recall helpers) and cap top-K.

### 1.2 Modern Swift Vision: `ClassifyImageRequest` (iOS 18+)

In the linked SDK Swift interface:

```swift
@available(iOS 18.0, *)
public struct ClassifyImageRequest : ImageProcessingRequest {
  public typealias Result = [ClassificationObservation]
  public var supportedIdentifiers: [String] { get }
  // revision2, cropAndScaleAction, async perform(on:)
}
```

Same conceptual job as `VNClassifyImageRequest`, with Swift concurrency-friendly `perform(on:)` and `ClassificationObservation` (also has precision/recall filters).

**ScreenTidy deployment target today: iOS 17.0.**  
→ Prefer **`VNClassifyImageRequest` + Revision 2** for production compatibility now.  
→ Optionally adopt `ClassifyImageRequest` behind `#available(iOS 18, *)` later, or after raising the deployment target.

### 1.3 Feature prints / visual similarity

| API | Detail |
|-----|--------|
| Legacy | `VNGenerateImageFeaturePrintRequest` → `VNFeaturePrintObservation` |
| Modern (iOS 18+) | `GenerateImageFeaturePrintRequest` → `FeaturePrintObservation` |
| Revisions | Rev1 tied to Classify Rev1; **Rev2 (iOS 17+)** tied to Classify Rev2 |
| Distance | `computeDistance(to:)` / Swift `distance(to:)` → lower = more similar |
| Nature | Compact **embedding-like fingerprint**, not human labels |

Feature prints are the right primitive for **local visual clustering / neighbor discovery**, not for Collection titles.

### 1.4 Related Vision APIs (relevant, not primary)

| API | Fit |
|-----|-----|
| `VNRecognizeTextRequest` | **Already used** (`VisionOCRService`) |
| `RecognizeDocumentsRequest` (iOS 26+) | Future document structure; out of scope for this proposal |
| Custom `VNCoreMLRequest` | Only if Apple taxonomy is insufficient; avoid for MVP visual layer |

---

## 2. Expected behavior on screenshots (not camera photos)

Apple’s classifier is a **general photo/scene model**, not a screenshot-UI model. Expectations:

| Screenshot type | Likely Vision value | Caveat |
|-----------------|---------------------|--------|
| Travel photo saved/shared as screenshot | High (airplane, beach, landmark-ish scenes) | Labels are generic (“airplane”), not “Japan Trip” |
| Product / food / car / pet imagery | Medium–high object labels | Easy to over-create “Cars” / “Food” folders if misused |
| Memes | Low–medium (person, indoor, cartoon…) | OCR + cultural context matter more |
| UI / design inspiration | Low–noisy (screen, electronics, indoor) | Classifier may see “monitor/laptop” not “Figma frame” |
| Text-heavy receipts / chats | Low visual; OCR dominates | Vision should not override OCR |
| Illustrations / art | Variable | May return style/object noise |
| Pure white UI / sparse icons | Weak / empty top labels | Stay in Needs Review offline |

**Conclusion:** Vision is valuable **evidence**, especially when OCR is empty/weak, but screenshot chrome and UI make confidence noisier than for Camera roll photos. Treat labels as soft signals with aggressive filtering.

---

## 3. Labels, confidence, and filtering strategy

### 3.1 What labels look like

Runtime identifiers are Apple’s fixed taxonomy (~1303 strings), e.g. objects/scenes such as animals, food, vehicles, indoor/outdoor, household items (exact set via `supportedIdentifiers`). They are **category vocabulary**, not contextual Collection names.

### 3.2 Are confidences reliable enough for the resolver?

**Yes as bounded evidence; no as sole authority.**

Recommended use:

1. Keep top **K ≤ 8** labels after filtering  
2. Prefer `hasMinimumPrecision(0.3, forRecall: 0.5)`-style gates **or** a high confidence floor (calibrate on device; start conservative, e.g. ≥ **0.25–0.40** after precision filter — tune in DEBUG, do not ship permissive)  
3. Map retained labels → `visualDescriptors` / `entities(type: "visual")` — **never** → `proposedNewCollection.title`  
4. Cap visual contribution inside existing resolver scoring (today `textVisualAgreement` is only **0.05–0.08**)  
5. Expand denylist with common Vision nouns (`airplane`, `cat`, `dog`, `car`, `food`, `person`, `indoor`, …) so create corroboration cannot mint them as titles

Wrong high-confidence generic labels are expected; the architecture must absorb that without filing wrongly.

### 3.3 Low-value / noisy label filter (proposed)

Drop or down-weight:

- Ultra-generic: `indoor`, `outdoor`, `person`, `people`, `screenshot`-adjacent electronics noise when OCR shows UI chrome  
- Near-duplicates / taxonomy parents if a child is stronger  
- Anything below calibrated floor  
- Labels that collide with `ResolverPolicy.genericTitleDenylist` when considering create paths  

Keep as evidence:

- Travel-ish clusters: airplane + airport + luggage (still evidence for an *existing* trip Collection, not “Airplanes”)  
- Food / product / pet when **combined** with OCR entities, time neighbors, or profile match  

---

## 4. Feature prints for local clustering

### 4.1 Opportunity

Today `OrganizationBatchPlanner` clusters only on:

- temporal proximity (2h / 12h / 48h)  
- OCR token Jaccard  

When OCR is empty, batches collapse to **time-only** (or singleton). Feature-print distance can recover **visually similar image-only groups** (design boards, meme variants, product series).

### 4.2 Proposed use

1. Compute feature print once per screenshot (Rev2), cache blob + version  
2. When planning a batch, score neighbors with:  
   `α·time + β·OCR Jaccard + γ·featurePrintSimilarity`  
3. Keep max batch **8**; raise visual weight only when OCR weak  
4. Similarity is for **corroboration / sharedContext hints**, not auto-create  

Distance thresholds must be calibrated on device (Apple does not publish a universal “same scene” cutoff). Start DEBUG-only metrics before using for create corroboration.

---

## 5. Current ScreenTidy implementation (inspected)

End-to-end today:

```
Photos sync → OCR queue (VNRecognizeTextRequest only)
  → OrganizationQueue → OrganizationService
    → OrganizationBatchPlanner (time + OCR)
    → UnderstandingProviding
         Composite → gateway multimodal (consent) OR on-device OCR heuristics
    → CollectionResolver (sole authority)
    → GRDB apply + profiles + organization_run
```

### Already exists (reuse — do not duplicate)

| Area | Location |
|------|----------|
| OCR Vision service | `ScreenTidy/Data/OCR/VisionOCRService.swift` |
| OCR queue / claim / version | `OCRProcessingQueue`, `OCRPipeline` |
| Org queue / service | `OrganizationQueue`, `OrganizationService` |
| Understanding contract | `UnderstandingProviding`, `ScreenshotUnderstanding` (`visualDescriptors`, entities, typeFacets) |
| Providers | `CompositeUnderstandingProvider`, `EphemeralMultimodalUnderstandingProvider`, `OnDeviceStructuredUnderstandingProvider` |
| Resolver + corroboration | `CollectionResolver`, thresholds 0.70 / 0.85 |
| Batch planner | `OrganizationBatchPlanner` |
| Image loaders / encode | `PhotoKitOCRImageLoader`, `PhotoKitMultimodalImageLoader`, `MultimodalImageEncoder` |
| Schema placeholders | `screenshot.visual_labels_json`, profile `visual_descriptors_json` |
| DEBUG inspector | `ResolverDebugInspectorView` (already shows visual descriptors + score breakdown) |
| Consent / privacy | `CloudUnderstandingPreferences`, gateway key isolation |

### Missing (greenfield Vision work)

- Any `VNClassifyImageRequest` / feature-print usage  
- Writers that fill `visual_labels_json`  
- Profile refresh that persists real visual descriptors (today refresh writes `visual_descriptors_json = '[]'`)  
- Batch planner visual similarity  
- On-device provider that consumes Vision labels for image-only shots (today empty OCR → `visualDescriptors: ["image_only"]` and **no candidates**)

**Vision classification is not a parallel product system** — it should feed the existing understanding → resolver path.

---

## 6. Architecture comparison

### A — Cloud multimodal only (current Sprint 8 remediation direction)

| Pros | Cons |
|------|------|
| Best contextual naming (“Japan Trip”) | Needs consent + network + working LAN/gateway on device |
| Handles memes/UI/intent | Offline / declined → weak OCR heuristic |
| Fits existing gateway | Image-only without cloud ≈ Needs Review forever |

**Accuracy when online:** strongest contextual. **Coverage offline:** weak.

### B — Apple Vision only

| Pros | Cons |
|------|------|
| Fully on-device, private, free | Labels ≠ contexts → wrong Collection names if naïvely used |
| Helps image-only object/scene evidence | Poor on UI/memes/intent |
| Feature prints help clustering | Cannot invent “Visa Application” / trip narratives from pixels alone |

**Accuracy for ScreenTidy’s product concept:** insufficient alone. Risk of category folders (“Cats”, “Airplanes”) is product-breaking.

### C — Hybrid (recommended)

```
Screenshot
  → On-device signals
       OCR (existing)
       Vision classification (new evidence)
       Feature print (new clustering)
       metadata/date (existing)
  → Context understanding
       Collection profiles (existing)
       batch neighbors (enhanced)
       optional multimodal AI when consent + reachable
  → Local Collection Resolver (unchanged thresholds)
  → reuse / create(+corroboration) / Needs Review
```

| Pros | Cons |
|------|------|
| Offline floor above today’s OCR-only stand-in | More pipeline complexity + storage |
| Cloud still used where it uniquely helps | Calibration work for thresholds / denylist |
| Aligns with privacy-first + existing contracts | Does not magically fix gateway LAN bugs |
| Classification accuracy prioritized via resolver gates | Must resist turning labels into titles |

**Priorities met:** accuracy > coverage > cost — Vision raises offline evidence without lowering thresholds or inventing Collections from nouns.

---

## 7. Recommended architecture (C) — data flow

```
PhotoKit bytes
    │
    ├─► OCR pass (existing queue)
    │     persist ocr_text + status
    │
    └─► Visual pass (new, same or adjacent queue)
          VNClassifyImageRequest (Rev2) → filtered labels[]
          VNGenerateImageFeaturePrintRequest (Rev2) → blob
          persist visual_labels_json + feature_print + versions
                │
                ▼
OrganizationService.organizeIfNeeded
    BatchPlanner(time + OCR + featurePrint)
    Build UnderstandingInput (+ cached visual labels)
                │
        ┌───────┴────────────────────────┐
        ▼                                ▼
 On-device understanding            Gateway multimodal
 (OCR + Vision labels as           (when consented & reachable)
  descriptors/entities;             may refine summary/candidates;
  NEVER propose "Cats")             Vision still used for local
                                    corroboration / caching
                │
                ▼
     CollectionResolver (0.70 / 0.85 + corroboration)
                │
                ▼
     reuse | create | Needs Review
```

### Hard product rule (locked)

> Vision classifications are **evidence**, never Collection names.  
> `airplane + airport` may raise confidence toward **Japan Trip**; they must not create **Airplanes**.

Enforcement points:

1. On-device provider: no `proposedNewCollection` from Vision identifiers alone  
2. Expand `genericTitleDenylist` with Vision noun list  
3. Create corroboration continues to require specific title / entity / batch rules  
4. Inspector shows Vision labels separately from Collection decision  

---

## 8. Exact integration points (existing code)

| Concern | Integration |
|---------|-------------|
| Run Vision | New `VisionImageUnderstandingService` next to `VisionOCRService` — **do not** fork PhotoKit loaders; reuse `PhotoKitOCRImageLoader` / shared downscale policy (classify long-edge ~1024–1800; calibrate) |
| Scheduling | Prefer **piggyback after OCR** in `OCRProcessingQueue` or a sibling `VisualSignalQueue` with same claim/version pattern — avoid unbounded parallel Vision storms |
| Persist labels | Fill existing `screenshot.visual_labels_json` (+ new columns for feature print / versions — see §10) |
| Understanding | Extend `OnDeviceStructuredUnderstandingProvider` to read cached labels → `visualDescriptors` / `entities(type:"visual")` |
| Composite | Pass local visual signals into gateway payload as compact context (optional); still no OpenAI keys on device |
| Batching | Extend `OrganizationBatchPlanner.score` with feature-print similarity |
| Profiles | `refreshCollectionProfile` should aggregate **filtered** visual descriptors (stop writing empty `[]`) |
| Resolver | Keep thresholds; optionally add small `visualProfileMatch` component **capped**; strengthen denylist |
| DEBUG | Resolver Inspector: show top Vision labels + confidences + print version; OCR Inspector sibling or shared “Visual signals” block |
| Fingerprint | Include visual signal version in organize content fingerprint so reprocess is intentional |

**Do not** bypass `CollectionResolver`. **Do not** create a second “Vision Collections” system.

---

## 9. Offline vs online behavior

| Mode | Behavior |
|------|----------|
| Offline / cloud declined | OCR + Vision labels + feature-print batches + profiles → on-device understanding → resolver. More image-only **reuse** possible; **create** still rare (needs corroboration + specific title — usually NR without OCR/entities) |
| Online + consented + gateway healthy | Multimodal proposes contextual candidates/summaries; local Vision still supports batching, offline cache, and text–visual agreement |
| Online but gateway unreachable | Same as offline floor (fixes the current acceptance pain for image-only without pretending labels are contexts) |

**When cloud multimodal remains necessary**

- Contextual Collection naming (“Japan Trip”, “Visa Application”)  
- Meme / UI / design intent beyond object nouns  
- Disambiguation across similar visuals with different life meaning  
- High-quality summaries and entity extraction from mixed UI+image shots  

Vision reduces **blindness**; it does not replace **context**.

---

## 10. Caching / persistence strategy

### 10.1 Cache once

| Signal | Persist | Invalidate when |
|--------|---------|-----------------|
| Classification labels + confidences + revision | `visual_labels_json` (exists) + `visual_classify_version` (new) | Pipeline version bump / explicit reprocess |
| Feature print blob + revision | `feature_print blob` + `feature_print_version` (new) | Same |
| Derived “top labels” for profiles | rolled into `collection_context_profile.visual_descriptors_json` | Membership changes (existing refresh) |

Suggested versions: `visualClassifyVersion = 1`, `featurePrintVersion = 1` (bump with algorithm changes).

### 10.2 Schema (proposed migration `v9_visual_signals` — future work)

- `screenshot.visual_labels_json` — already present; start writing  
- `screenshot.visual_classify_status` / `visual_classify_version` / `visual_classify_error` (mirror OCR claim pattern lightly)  
- `screenshot.feature_print` BLOB (or file URL in Application Support if large)  
- `screenshot.feature_print_version`  
- Optional: `screenshot.visual_top_labels` denormalized for inspector  

Understanding cache fingerprint must include visual versions so stale multimodal caches are not mixed incorrectly.

### 10.3 Performance (hundreds / thousands)

| Concern | Mitigation |
|---------|------------|
| CPU/Neural Engine | Serial/low concurrency (1–2), background QoS, pause when thermal/battery constrained |
| Decode cost | Reuse OCR CGImage when still warm; else downscale once for both classify + feature print |
| Storage | Feature prints are small vs JPEG; still version + prune soft-removed |
| Organize latency | Visual pass **ahead of** organize (like OCR); organize reads cache only |
| Reprocess storms | Version gates; no mass reclassify on launch (same rule as resolverVersion) |

Rough expectation: classify + feature print per screenshot is typically tens–low hundreds of ms on modern iPhones when downscaled — acceptable if queued like OCR, not on the UI path.

---

## 11. Confidence strategy (resolver-aligned)

Keep locked:

- assign ≥ **0.70**  
- create ≥ **0.85** + corroboration  
- reuse-before-create  
- user locks  
- user Collection auto-add **OFF**

Vision adjustments (conceptual — not implemented):

1. Map filtered labels → descriptors (evidence only)  
2. `textVisualAgreement`: allow Vision↔OCR / Vision↔profile agreement to contribute within existing small caps  
3. Batch corroboration: feature-print neighbors can satisfy “batch support” when OCR empty  
4. Create path: Vision-only evidence **never** enough for create without a specific non-denylisted title + other corroboration  
5. Conflicts: if Vision says “furniture” but OCR clearly “boarding pass”, apply conflict penalty (extend existing heuristic)  

---

## 12. Expected benefits

1. Image-only / weak-OCR screenshots gain **local evidence** instead of empty `image_only`  
2. Better local batches for design/meme/product series via feature prints  
3. Stronger offline / declined-consent floor without opening category-folder hell  
4. Multimodal gateway becomes **selective refinement**, not the only visual path  
5. Privacy: classification + prints stay on device; no new cloud dependency  
6. Fits Sprint 4–7 architecture (Photos → OCR → organize → resolver) without rewriting them  

---

## 13. Risks

| Risk | Mitigation |
|------|------------|
| Generic Collections (“Cats”, “Airplanes”) | Hard ban: no title from identifiers; denylist; create corroboration |
| Screenshot UI noise | Higher filters; down-weight electronics/indoor when OCR looks like UI |
| Over-trusting confidence | Cap visual score contribution; prefer NR |
| Battery / thermal on large libraries | Queue + concurrency caps + versioned cache |
| Dual API surface (iOS 17 VN* vs iOS 18 Swift) | Standardize on VN* Rev2 until deployment target ≥ 18 |
| Scope creep into Sprint 8 | Keep Vision out of Sprint 8 acceptance; separate approval |
| False visual batches merge unrelated trips | Require time window + distance threshold; prefer NR |

---

## 14. Implementation phases (after approval — not now)

### Phase 0 — Spike (1–2 days, DEBUG device)
- Classify + feature-print on 30–50 real screenshots (travel, meme, UI, food, product, text-only)  
- Log top labels / distances in DEBUG  
- Decide filter floors  

### Phase 1 — Persist visual signals
- Service + queue piggyback + schema writers  
- Inspector surfaces labels  
- No resolver behavior change yet  

### Phase 2 — On-device understanding + batching
- Feed labels into on-device provider  
- Feature-print batch scoring  
- Denylist expansion  
- Unit tests  

### Phase 3 — Resolver tuning (still no threshold lowering)
- Profile visual descriptors refresh  
- Calibrated agreement / conflict  
- Eval labels on device  

### Phase 4 — Multimodal interaction
- Send compact local labels to gateway as hints (optional)  
- Document offline vs online matrix in `docs/07` / `08`  

---

## 15. Test plan

### Unit tests

- Label filter: drops low confidence / denylisted nouns  
- On-device provider: Vision labels populate descriptors; **do not** propose Collection titled “Cat” / “Airplane”  
- Create corroboration rejects Vision-noun titles  
- Batch planner: feature-print similarity ranks neighbors when OCR empty  
- Fingerprint changes when visual version bumps  
- Resolver thresholds unchanged (lock tests)  

### Physical-device acceptance tests

1. Image-only travel screenshots: may **reuse** Japan Trip when profile/neighbors agree; must **not** create “Airplane”  
2. Pet / food / car image-only: prefer Needs Review or reuse existing context — never generic object Collections  
3. Text-heavy receipt: OCR dominates; Vision noise does not flip filing  
4. Meme with weak OCR: usually Needs Review offline; cloud multimodal still needed for good naming  
5. Design UI screenshots: classify may be weak; feature-print clustering of similar frames OK for batch, not auto-create  
6. 500+ library soak: queue completes without UI jank; no repeated reclassify  
7. Airplane mode: organizes with local signals; no crash; no key use  
8. DEBUG Inspector shows Vision labels + decision provenance  

---

## 16. Should this join Sprint 8 remediation?

| Option | Recommendation |
|--------|----------------|
| Expand Sprint 8 acceptance to require Vision | **No** |
| Use Vision to unblock Sprint 8 gateway LAN issues | **No** — orthogonal; fix gateway URL/bind/firewall separately |
| Approve Vision design now, implement after Sprint 8 device acceptance (or parallel spike only) | **Yes** |

**Rationale:** Sprint 8’s approved remediation is multimodal gateway + structured understanding + resolver corroboration. Physical-device gateway connectivity is a Sprint 8 blocker. Vision improves the **offline / image-only** floor and reduces over-reliance on cloud, but:

- It does not complete Sprint 8’s multimodal acceptance criteria  
- Shipping Vision mid-remediation risks conflating eval results  
- Product risk (category folders) needs its own careful acceptance  

**Proposal:** keep Sprint 8 focused on gateway + multimodal accuracy acceptance; schedule **Visual Signals / Hybrid Vision** as the next approved track after (or as a non-blocking spike alongside) Sprint 8 — **still not Sprint 9 product scope unless you explicitly rename/prioritize it**.

---

## 17. Decision checklist for you

Please approve or revise:

1. Architecture **C (Hybrid)** as the target  
2. Vision labels = **evidence only** (never Collection titles) — locked  
3. Prefer **`VNClassifyImageRequest` Revision 2** + **feature-print Revision 2** while deployment target is iOS 17  
4. **Defer implementation** from Sprint 8 acceptance; optional DEBUG spike only if you want data first  
5. Keep thresholds **0.70 / 0.85 + corroboration** unchanged  

---

## STOP

Research + proposal complete.  
**No code changes made. Sprint 9 not started. Sprint 8 remains NOT ACCEPTED.**  
Awaiting your approval before any implementation.
