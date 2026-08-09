# ScreenTidy Intelligence Architecture — Multi-Signal Contextual Organization

**Status:** **APPROVED** (2026-08-09) — Architecture **C** locked as production target  
**Sprint 8:** remains **IMPLEMENTED BUT NOT ACCEPTED**  
**Sprint 8 product gate:** materially useful automatic organization on real device screenshots — **not** infrastructure-only  
**Sprint 9:** **NOT STARTED** (blocked until Sprint 8 organization quality is accepted)  
**Implementation:** Incremental phases **P0→P6**; measure after each phase; do not skip ahead to P1 until P0 device smoke passes  

**Related:**  
- `reviews/vision-visual-signals-research-proposal.md` (Vision evidence layer — approved within C)  
- `docs/24_SPRINT_8_COLLECTION_RESOLVER.md`  
- `docs/07_AI_PIPELINE.md`, `docs/08_PRIVACY_SECURITY.md`  
- `docs/25_RAILWAY_GATEWAY.md` (P0 hosted multimodal transport)

---

## Locked decisions (2026-08-09)

| # | Decision |
|---|----------|
| 1 | Architecture **C — Hybrid Multi-Signal Contextual Intelligence** |
| 2 | Vision classifications / type facets are **evidence only** — **never** Collection names |
| 3 | `VNClassifyImageRequest` Rev2 + `VNGenerateImageFeaturePrintRequest` Rev2 (iOS 17) |
| 4 | Feature prints = visual neighbors only (combine with other signals) |
| 5 | **Local text embeddings first**; cloud embeddings deferred; **no cloud vector DB** |
| 6 | Image/multimodal embeddings deferred until measured gap |
| 7 | Multi-signal clustering (conservative cohesion) |
| 8 | Multimodal AI prefers **cluster-level context** (≤ 8 images, minimized payload) |
| 9 | Richer local Collection profiles; reuse compares **context**, not titles alone |
| 10 | Local Collection Resolver = sole mutation authority |
| 11 | Reuse-before-create; assign ≥ **0.70**; create ≥ **0.85** + corroboration — **unchanged** |
| 12 | `source=user` absolute (Sprint 7) |
| 13 | Core ML custom classifier **deferred** |
| 14 | Sprint 8 stays open through enough of P1–P5 to prove product-quality improvement |
| 15 | Full stack stays in Sprint 8 remediation — **not** moved to Sprint 9 |

### Phase order (measure after each)

| Phase | Scope | Gate |
|-------|--------|------|
| **P0** | Hosted HTTPS multimodal baseline | Device smoke: iPhone → Railway → OpenAI → resolver → UI |
| **P1** | Vision classify + feature prints + persist + DEBUG | Measure (explicit approval before start) |
| **P2** | Multi-signal clustering (no embeddings yet) | Measure |
| **P3** | Local text embeddings + profile centroids | Measure |
| **P4** | Cluster-level selective multimodal | Measure |
| **P5** | Resolver multi-signal scoring | Measure |
| **P6** | Full evaluation / tuning | Sprint 8 acceptance candidate |

**P0 alone does not close Sprint 8.** Stop after P0 smoke; await explicit approval before P1.

---

## Executive verdict

**Architecture C — Hybrid multi-signal contextual intelligence** is the production target.

Stop treating each screenshot as an isolated OCR→classify→Needs Review problem. Build **local evidence records**, **multi-signal clustering**, then **selective multimodal context reasoning**, with the **local Collection Resolver** as sole authority.

| Option | Verdict |
|--------|---------|
| **A** — OCR + per-shot multimodal + resolver (current Sprint 8 shape) | Necessary transport/path, **insufficient product intelligence** alone |
| **B** — Apple-local only (OCR + classify + feature prints) | Strong offline floor; **cannot** name “Japan Trip” from nouns alone |
| **C** — OCR + Vision + similarity + embeddings + selective multimodal + resolver | **APPROVED production target** |

**Thresholds stay locked:** assign ≥ **0.70**, create ≥ **0.85** + corroboration. Improve evidence quality, do not lower bars.

**Vision labels and type facets never become Collection titles.**

---

## 1. Recommended final architecture

```
PHAsset (PhotoKit)
        │
        ▼
┌───────────────────────────────────────┐
│ LOCAL ANALYSIS (queued, versioned)    │
│  • Vision OCR (Sprint 5 — keep)       │
│  • VNClassifyImageRequest Rev2        │
│  • VNGenerateImageFeaturePrint Rev2   │
│  • metadata / createdAt               │
│  • internal type/facet hints          │
└───────────────────────────────────────┘
        │
        ▼
Local screenshot understanding record (GRDB)
        │
        ├── text embedding (preferred local; cloud fallback if needed)
        └── optional image / multimodal embedding
        │
        ▼
Multi-signal similarity + contextual grouping
  (OCR entities · embeddings · feature prints ·
   Vision labels · time · Collection profiles)
        │
        ▼
Candidate clusters (≤ 8 members for cloud; larger local graph OK)
        │
        ▼
Selective multimodal AI (hosted HTTPS gateway, consented)
  high-level CONTEXT proposal only
        │
        ▼
LOCAL Collection Resolver (sole authority)
        │
        ├── reuse existing Collection
        ├── create dynamic Collection (+ corroboration)
        └── Needs Review
```

**Core ML custom models:** future optional; not required for first hybrid ship.

---

## 2. Exact role of each technology

| Layer | Technology | Role | Must NOT |
|-------|------------|------|----------|
| Capture | PhotoKit / `PHAsset` | Source of truth for pixels + dates | Own Collections |
| Text | Vision OCR | Search substrate (raw) + org-normalized text | Be the only understanding signal |
| Visual labels | `VNClassifyImageRequest` Rev2 (iOS 17) | Object/scene **evidence** | Become Collection names |
| Visual similarity | `VNGenerateImageFeaturePrintRequest` Rev2 | Local **near-duplicate / visual neighbor** signal | Define membership alone |
| Type facets | Heuristic / multimodal / later Core ML | Internal `boarding_pass`, `hotel_booking`, … | Auto-create “Boarding Passes” folders |
| Semantic similarity | Embeddings (text ± image) | Relate boarding pass ↔ hotel ↔ map ↔ landmark photo | Replace resolver |
| Deep context | Multimodal AI via ScreenTidy gateway | Propose **Japan Trip**-level context + candidates | Mutate GRDB / Collections |
| Storage | SQLite / GRDB | System of record + compact vectors | Cloud vector DB |
| Authority | Collection Resolver | reuse / create / NR | Be bypassed by cloud |
| User | Sprint 7 locks | Absolute override | Be casually overwritten |

---

## 3. Data flow (end-to-end)

1. **Ingest** — PhotoKit sync upserts screenshot row (existing).  
2. **OCR pass** — existing queue; raw → FTS; org-normalized at organize time (existing).  
3. **Visual pass** (new) — classify top-K labels + feature-print blob; versioned; cached.  
4. **Facet pass** (light) — derive internal type hints from OCR patterns + Vision (bounded vocabulary).  
5. **Embedding pass** (new) — text embedding from org-OCR (+ optional compact image embedding later); cache by content hash + model version.  
6. **Cluster** — multi-signal graph around seed (new/pending shots + profile neighbors).  
7. **Understand**  
   - Offline: local evidence → on-device structured proposal (conservative).  
   - Online + consent: representative cluster payload → gateway multimodal → structured proposal.  
8. **Resolve** — local resolver with multi-signal confidence + corroboration.  
9. **Persist** — membership / Needs Review; refresh Collection profile (incl. visual + semantic centroid when available).  
10. **UI** — Home / Needs Review / Collections (unchanged product surfaces).

---

## 4. Local vs cloud signals

| Signal | Local | Cloud (consented) |
|--------|-------|-------------------|
| OCR | ✓ | Optional echo (normalized, truncated) |
| Vision classification | ✓ | Compact top labels as hints only |
| Feature print | ✓ never upload raw print unless proven necessary | Prefer **not** uploading prints |
| Embeddings | Prefer ✓ | Only if local quality insufficient; then ephemeral + cache |
| Type facets | ✓ / refine via multimodal | ✓ |
| Context title (“Japan Trip”) | Weak offline | ✓ primary strength |
| Collection mutation | ✓ only | ✗ never |
| Full library / full-res | ✗ | ✗ |

---

## 5. Embedding recommendation

### Goal
Relate **boarding pass + hotel + map + reservation + landmark photo** even when OCR and pixels differ.

### Options compared

| Approach | Quality | Privacy | Offline | Cost | Latency | Storage | Fit |
|----------|---------|---------|---------|------|---------|---------|-----|
| No embeddings (OCR Jaccard only) | Low for image-only / paraphrases | Best | Best | Free | Free | Tiny | Current gap |
| Local text embeddings (e.g. small on-device model / NLEmbedding-style / Core ML sentence encoder) | Good for OCR-rich | Excellent | Excellent | Free after model | Low–med | ~0.5–2 KB/shot × dim | **Phase 1 preference** |
| Apple Vision feature print as “visual embedding” | Good visual; weak cross-modal | Excellent | Excellent | Free | Low | Small blob | **Already recommended** — complementary, not sufficient alone |
| Server text embeddings (OpenAI/others via gateway) | High | Consent + egress | No | Per call | Network | Cache locally | Phase 1b if local quality fails eval |
| Server multimodal embeddings | Highest cross-modal | Heavier egress | No | Higher | Higher | Cache | Phase 2 if text+print still miss image-only clusters |
| Cloud vector DB | Ops overhead | Worst for local-first | No | Ongoing | Network | Remote | **Reject for MVP** |

### Recommended strategy

1. **Phase 1:** Local **text embeddings** on org-normalized OCR (empty OCR → skip text vector; rely on Vision print + labels).  
2. Keep **feature prints** as the visual similarity channel (do not pretend prints are semantic “Japan Trip” embeddings).  
3. **Evaluate** on device: if text-only local embeddings + prints fail the Japan-trip style set, add **gateway text embeddings** (OCR snippet only, consented, cached by hash).  
4. Defer **image/multimodal embeddings** until measured need.  
5. **Never** re-embed the whole library on launch; version `embedding_version`; incremental for new/changed content only.

**Provider choice:** do not lock a cloud embedding vendor until Phase 1 local eval fails. If cloud is needed, route through the existing ScreenTidy gateway (same privacy envelope as understand), not from the iOS binary.

---

## 6. Vision recommendation

Reaffirm and extend `reviews/vision-visual-signals-research-proposal.md`:

| API | iOS 17 choice | Persist | Use |
|-----|---------------|---------|-----|
| `VNClassifyImageRequest` **Revision 2** | ✓ | Top ≤ 8 `{id, confidence}` after precision/confidence filter | Evidence → `visual_labels_json` / descriptors |
| `VNGenerateImageFeaturePrintRequest` **Revision 2** | ✓ | Blob + version | Distance for visual neighbors |
| Modern Swift `ClassifyImageRequest` | iOS 18+ optional later | Same | Same taxonomy |

**Hard rule:** `furniture` + `sofa` → evidence for **Apartment Setup**, never Collection **Furniture**. Expand denylist with Vision nouns.

**Screenshot caveat:** classifier is photo/scene-oriented; UI/memes noisy — keep filters aggressive; OCR still dominates text-heavy shots.

---

## 7. Clustering strategy

Replace “independent shot + weak time/OCR batch” with **multi-signal candidate groups**.

### Signals (weighted, tunable)

| Signal | Example weight band | Notes |
|--------|---------------------|-------|
| Entity / location overlap | High | Tokyo, NRT, Park Hyatt |
| Text embedding cosine | High when OCR present | Semantic paraphrase |
| Feature-print distance | Medium–high when OCR weak | Visual series / landmark photos |
| Vision label Jaccard | Low–medium | Shared travel/furniture themes |
| Temporal proximity | Medium | 2h / 12h / 48h / trip windows |
| Collection profile match | High | Pull toward existing Japan Trip |
| Type-facet compatibility | Medium | boarding_pass + hotel_booking cohere; chat + receipt weaker |

### Rules

- No single signal defines a Collection.  
- Cluster for **proposal / corroboration**; resolver still decides membership.  
- Cloud batch ceiling remains **≤ 8** representatives (may summarize a larger local cluster).  
- Conflicting facets (e.g. strong “receipt” vs “boarding_pass”) reduce cluster cohesion / confidence.  
- Image-only members join via print + labels + time + profile, not automatic NR.

### Japan Trip example (target)

| Shot | Local signals |
|------|----------------|
| A boarding DOH→NRT | type=boarding_pass; entities DOH,NRT |
| B Park Hyatt Tokyo | type=hotel_booking; Tokyo |
| C Maps Tokyo | type=map; Tokyo |
| D restaurant reservation | type=reservation; Tokyo |
| E Tokyo Tower, no OCR | Vision landmark/city/travel; print near other travel imagery |

→ Multi-signal cluster A–E → multimodal proposes **Japan Trip** → resolver CREATE/REUSE (not five object folders).

---

## 8. Dynamic Collection naming strategy

| Source | Naming role |
|--------|-------------|
| Multimodal structured `contextTitle` | Primary proposer when online |
| Existing profile title / alias (≥ similarity / entity match) | **Reuse wins** |
| Local offline | Only high-corroboration, specific multi-token titles; else NR |
| Vision identifiers / type facets | **Never** titles |
| User titles | Immutable authority (Sprint 7) |

**Reuse before create** compares **context**, not string equality alone:

- entity overlap with profile  
- embedding proximity to profile centroid (when available)  
- date range overlap  
- alias / title similarity ≥ 0.90 (existing)  
→ Prefer **Japan Trip** over minting **Tokyo Vacation**.

Create still requires ≥ **0.85** + corroboration (batch / strong entities / agreement) and denylist checks.

---

## 9. Resolver changes required (conceptual — not implemented now)

Keep thresholds. Extend **evidence inputs** and scoring components:

| Change | Purpose |
|--------|---------|
| Ingest Vision labels + facet hints into understanding / profiles | Fill today’s empty `visual_descriptors` path |
| Add `embeddingSimilarity` / `visualPrintSimilarity` components (capped) | Multi-signal final confidence |
| Profile match against entities + embedding centroid + aliases | Context reuse |
| Cluster size / cohesion as corroboration | Create support without category folders |
| Stronger conflict penalties | Facet/Vision vs OCR disagreement |
| Deny Vision nouns + type keys as titles | Product rule |

**Do not** let cloud apply memberships. **Do not** lower 0.70 / 0.85.

---

## 10. Database changes (additive only)

Existing hooks to **use**, not duplicate:

- `screenshot.visual_labels_json` (empty today)  
- `collection_context_profile` (+ `visual_descriptors_json` currently wiped to `[]`)  
- `understanding_cache`, organize status / fingerprint / runs  

### Proposed additive migration (future `v9+`)

| Field / table | Purpose |
|---------------|---------|
| `visual_analysis_version` | Classify + print pipeline version |
| `visual_classify_status` (light) | Claim/retry like OCR if needed |
| `feature_print` BLOB + `feature_print_version` | Similarity |
| `embedding_version` + `embedding` BLOB (or float blob) | Semantic vector |
| `embedding_model_id` TEXT | Provenance |
| `internal_facets_json` | Bounded type signals |
| `cluster_id` / `cluster_version` (nullable) | Last local cluster assignment (debug/corroboration) |
| Profile: `embedding_centroid` + version | Reuse matching |
| Analysis content hash | Skip recompute |

**MVP storage:** SQLite BLOBs + brute-force top-K among recent/pending candidates (correctness first). ANN only if 10k+ eval proves lag.

---

## 11. Performance / cost

| Scale | Strategy |
|-------|----------|
| 100 | Full local analysis fine; multimodal for ambiguous clusters |
| 1,000 | Queues concurrency 1–2; cache everything; multimodal selective |
| 10,000+ | Incremental only; neighbor search limited to time window + LSH/ANN later if needed |

**Cost control**

- Never full-res to cloud (1024 / 0.75).  
- Multimodal on **cluster representatives**, not every shot.  
- Embeddings computed once per version.  
- Hosted gateway + shared secret (Railway path) for abuse control.  
- OpenAI $ dominates; local Vision/embeddings are “free” CPU.

**UI:** analysis off main thread; Home/Search unaffected; no reanalysis on every launch.

---

## 12. Privacy

- Local-first: OCR, Vision, prints, embeddings stay on device by default.  
- Cloud: consented, ephemeral, minimized (OCR summary + few JPEGs + compact profiles + optional label hints).  
- No cloud vector DB; no library dump.  
- Gateway never mutates Collections; no durable screenshot store.  
- Retention claims follow **real** OpenAI account config — no unverified ZDR.  
- User locks remain absolute.

---

## 13. Offline behavior

When multimodal unavailable / declined:

**Available:** OCR, Vision labels, feature prints, local embeddings (if shipped), dates, profiles, clustering.  

**Allowed outcomes:** high-confidence **reuse** when profile/entity/embedding agreement is strong; rare offline **create** only with specific title + corroboration.  

**Default when unsure:** Needs Review — never force bad offline filing.  

Image-only offline: can join visual clusters and reuse a strong profile; should not invent “Cats” / “Airplanes”.

---

## 14. Implementation phases

| Phase | Scope | Outcome |
|-------|--------|---------|
| **P0** | Hosted HTTPS multimodal baseline (in progress) | Prove iPhone → Railway → OpenAI → resolver on **one** shot |
| **P1** | Vision classify + feature print + persist + Inspector | Local visual evidence; better batches |
| **P2** | Multi-signal clustering (time+OCR+print+labels+profiles) | Japan-trip style groups without embeddings |
| **P3** | Local text embeddings + profile centroids | Cross-OCR semantic links |
| **P4** | Multimodal on **clusters** (not isolated shots) | Context naming quality jump |
| **P5** | Resolver scoring uses new signals (caps; no threshold drop) | Measurable accuracy lift |
| **P6** | Eval suite + tune filters | Accept/reject Sprint gate |
| **Later** | Cloud embeddings / image embeddings / Core ML / ANN | Only if P3–P5 metrics demand |

**Core ML:** see §5 appendix — dataset/types/cost; **not** in early phases.

---

## 15. What belongs in Sprint 8 remediation vs later

| Sprint 8 (this milestone — stays open) | Not Sprint 9 dumping ground |
|----------------------------------------|------------------------------|
| **P0** Hosted HTTPS multimodal baseline + device smoke | Do **not** close Sprint 8 on P0 alone |
| **P1–P5** as required by measured accuracy | Intelligence stack remains Sprint 8 remediation |
| Product-quality auto-organization on real corpus | Sprint 9 blocked until Sprint 8 accepted |
| DEBUG eval / trust-before-coverage | Core ML, cloud embeddings, ANN — only if eval demands |

**Sprint 8 acceptance** requires materially useful automatic organization (low wrong-file, contextual naming, reuse, image-only not doomed to NR) — not merely “gateway reachable.”

**P0 smoke → stop → explicit approval before P1.**

---

## 16. Physical-device evaluation strategy

Use existing Resolver Inspector eval labels + aggregate metrics.

### Corpus (representative)

- **Text:** bookings, receipts, chats, websites  
- **Mixed:** products, Maps, social, restaurant pages  
- **Image-only:** furniture, travel, food, design, fashion  

### Metrics (trust > coverage)

- Correct Collection / wrong Collection  
- Correct reuse / correct create / wrong name  
- Needs Review rate (and “should have been NR”)  
- Image-only success  
- Duplicate Collection creation  

### Gates

- Wrong-file rate must not rise vs baseline.  
- Image-only must leave “always NR” plateau.  
- Japan-trip-style multi-shot contexts should cluster + name without object folders.  
- Offline path must not create generic Vision-noun Collections.

---

## Architecture comparison (validation of C)

### A — Current OCR + multimodal + resolver
- **Pros:** Real contextual model when connected; gateway/privacy model exists.  
- **Cons:** Per-shot isolation; weak image-only; weak cross-shot semantic links; LAN friction (being replaced by Railway); mostly NR on hard real data.  
- **Role going forward:** **transport + deep context module**, not the whole brain.

### B — Apple-local only
- **Pros:** Private, offline, free, fast visual evidence.  
- **Cons:** Labels ≠ contexts; cannot reliably produce “Japan Trip”; risk of category folders if misused.  
- **Role:** **mandatory local substrate**.

### C — Hybrid (recommended)
- Local stack answers *what’s on the screen / what’s similar / what’s nearby in time*.  
- Embeddings answer *what’s about the same meaning*.  
- Multimodal answers *what life context binds them* and proposes names.  
- Resolver enforces trust thresholds and user authority.  

This matches the product problem statement and the locked resolver philosophy.

---

## Appendix — Core ML (future optional)

| Question | Answer |
|----------|--------|
| When? | After Vision+embeddings+cluster multimodal still miss screenshot-specific types |
| Dataset | Hundreds–thousands of labeled screenshots: boarding_pass, hotel_booking, receipt, chat, map, product_page, design_reference, … |
| Benefit | Better internal facets on UI screenshots where ImageNet-style Vision fails |
| Cost | Labeling, Create ML / training loop, per-OS revalidation, model size, bias/drift |
| Preference | Built-in Vision first; Core ML only with measured gap |

---

## Decision checklist (for you)

~~Awaiting approval~~ — **APPROVED 2026-08-09** (see Locked decisions above).

Next action: **P0 only** (hosted HTTPS multimodal). After device smoke passes, await explicit approval before **P1** Vision.
