# Sprint 8 — Collection Resolver / Automatic Organization

**Status:** **IMPLEMENTED BUT NOT ACCEPTED** (2026-08-09) — automatic organization milestone remains open  
**Physical-device:** Hosted HTTPS gateway (**P0**) required; LAN Mac gateway is not the acceptance path  
**Product gate:** Materially useful auto-organization on real screenshots (Architecture **C** phases as needed) — **not** “gateway works” alone  
**Depends on:** Sprint 4–7 — all **CLOSED / ACCEPTED**  
**Canonical roadmap:** `docs/13_IMPLEMENTATION_ROADMAP.md` § Sprint 8  
**Related:** `docs/07_AI_PIPELINE.md`, `docs/06_DATA_MODEL.md`, `docs/08_PRIVACY_SECURITY.md`, `docs/25_RAILWAY_GATEWAY.md`  
**Intelligence architecture (APPROVED):** `reviews/intelligence-architecture-multisignal-proposal.md`

**Completion report:** `reviews/sprint-08-completion-report.md`  
**Accuracy plan:** `reviews/sprint-08-accuracy-improvement-plan.md` (**APPROVED**)  
**Gateway:** `gateway/README.md`  
**Sprint 9 must NOT start until Sprint 8 is accepted.**

---

## Accuracy remediation (APPROVED 2026-08-09)

| Decision | Implementation |
|----------|----------------|
| Stateless ScreenTidy HTTPS gateway | `gateway/` — iOS never holds provider keys |
| Initial model GPT-5.6 Terra | Gateway `OPENAI_MODEL` (default `gpt-5.6`); replaceable |
| Structured output | Server Zod + on-device decode; malformed → no Collection mutation |
| Image 1024 / JPEG ~0.75 | `MultimodalImagePolicy` (tunable) |
| OCR + image together | Org-normalized OCR + JPEG when consent accepted |
| Thresholds 0.70 / 0.85 | Unchanged; **create corroboration** required |
| Batch ≤ 8 | `OrganizationBatchPlanner` + `ResolverPolicy.maxBatchSize` |
| Collection context profiles | `collection_context_profile` (local, bounded) |
| Multi-signal confidence | `ResolverConfidenceComponents` in Inspector |
| DEBUG eval + reprocess | Resolver Inspector labels + Needs Review re-run |
| `resolverVersion` | **2** |

**Authority unchanged:** cloud proposes; local resolver decides; user locks honored.

---

## Product outcome (LOCKED)

```
New screenshot
  → understand (hybrid)
  → LOCAL Collection Resolver decides
  → reuse Collection | create Collection | Needs Review
```

**Needs Review = uncertainty fallback, not the dump.**  
**Trust > coverage.** Incorrect automatic filing is worse than leaving a shot in Needs Review.

Do **not** optimize Sprint 8 by artificially shrinking Needs Review.

---

## Final architecture decisions (APPROVED 2026-08-08)

### 1. Hybrid — APPROVED

| Layer | Owns |
|-------|------|
| **On-device** | PhotoKit, OCR, GRDB, Collection graph, existing titles, **resolver decision logic**, thresholds, provenance, Needs Review, retries/state, **final membership mutation** |
| **Optional ephemeral cloud** | Minimal payload in → structured candidates out |

**Cloud proposes. Local resolver decides.**

Cloud must **never** directly:
- create Collection records  
- move / remove screenshots  
- remove from Needs Review  
- override user assignments  

### 2. Thresholds — INITIAL tunables (not permanent constants)

| Policy | Initial default |
|--------|-----------------|
| `ResolverPolicy.assignThreshold` | **0.70** |
| `ResolverPolicy.createThreshold` | **0.85** |

Centralized / configurable. Tune against real screenshots without schema churn.  
DEBUG Inspector must show proposed confidence, applicable threshold, and decision.

### 3. Err on trust — APPROVED

If signals disagree substantially → **Needs Review**.

### 4. User-created Collection auto-add — OFF

Resolver does **not** auto-attach into `user_context` / `created_by = user` Collections.  
Visible + manually assignable only.  
**No** per-Collection “Allow auto-organize” UI in Sprint 8.

### 5. Resolver-created Collections — reuse OK

`ai_context` Collections **do** accept future automatic attaches when reuse confidence ≥ assign threshold.

### 6–7. Network disclosure — REQUIRED; decline keeps app usable

Before **first** screenshot-derived cloud upload, explicit choice.  
Decline → Photos sync, OCR, Search, manual org, Needs Review still work; auto-org reduced/unavailable.  
Store preference locally. Distinct from Photos permission.

### 8. Minimal cloud payload

Send only: normalized OCR, small thumb when visual needed, creation date, limited metadata, compact **automatic** Collection titles, opaque correlation id.  
Never: full-res originals, whole library, full membership graphs, unrelated shots.

### 9. Image-only — multimodal attempt

Empty OCR ≠ automatic Needs Review.  
Pipeline: no OCR → multimodal → resolver → Collection / NR if still weak.  
No hallucinated Collections from loose recognition.

### 10–11. Signals + structured output

OCR + visual descriptors + entities + dates + existing automatic Collection context.  
No full embedding graph required in Sprint 8.  
**Structured validated JSON only** — schema/confidence/title validation; malformed → safe fallback; **no direct DB mutation from model**.

### 12–14. Reuse-before-create + minimal internal aliases

Normalize + light fuzzy + alias lookup.  
No aggressive semantic merge.  
Aliases **internal only** — no Merge UI / alias editor (Phase C deferred).  
Alias only on strong equivalence; uncertain → do not alias.

### 15–17. Create rules + title quality + emoji

Create only if ≥ create threshold AND no strong reuse candidate AND title quality passes AND not generic denylist.  
Titles: concise, 1–4 words, context-specific, no sentences / model reasoning.  
One emoji grapheme from proposal; user may change later (user-authoritative).

### 18–19. User authority + corrections

`source = user` is a **hard invariant**.  
Manual Move/Add/Remove/rename/emoji win.  
Corrections persist; never auto-move back. No uncontrolled self-learning.

### 20–21. No thrashing + `resolver_version`

Do not re-resolve accepted assignments on every launch.  
Version organization; reprocess only for explicit reasons (version upgrade strategy, still-NR, user request later).

### 22–24. Backlog / incremental / offline

Bounded queue, no giant library prompts, UI stays responsive.  
New shot: sync → OCR → understanding → resolver → Collection | NR.  
Offline: `pendingNetwork` (or equivalent); manual org works; retry with backoff.

### 25–28. Failure / cost / DEBUG / logging

Preserve screenshot + graph; NR where appropriate.  
Cost: no unnecessary reprocess, concurrency/retry caps, cache, OCR-only when sufficient, multimodal when useful.  
**DEBUG Resolver Inspector required.**  
Production logs: metadata only — never images/OCR/payloads/user content.

### 29–31. Device eval / success metrics / exclusions

See checklists below. Metrics: correct reuse/create, duplicates, incorrect filing, NR rate, corrections, latency, failures — **not** “NR emptied.”  
Exclusions: Merge UI, pin/archive/favorites, AI chat, PhotoKit org delete, cloud sync, autonomous user-override, uncontrolled learning.

---

## Decision flow (LOCKED)

```
Screenshot (OCR done | empty OCR finalized)
  → Gate (inaccessible / removed / user-locked / already resolved this version)
  → Build understanding input
  → Understanding provider (cloud if consented+online; else pendingNetwork / skip)
  → Validate structured output
  → On-device CollectionResolver ONLY:
        max conf < assignThreshold     → Needs Review
        match eligible ai Collection   → REUSE (source=ai)
        no match + ≥ createThreshold   → CREATE ai_context + attach
        else                           → Needs Review
  → Persist run + provenance; never mutate from raw model
```

---

## ResolverPolicy (conceptual)

```text
ResolverPolicy.assignThreshold = 0.70   // tunable
ResolverPolicy.createThreshold = 0.85   // tunable
ResolverPolicy.userCollectionAutoAdd = false
ResolverPolicy.resolverVersion = N
```

---

## Structured understanding contract (conceptual)

```json
{
  "summary": "...",
  "entities": [{ "type": "city", "value": "Tokyo", "confidence": 0.86 }],
  "visualDescriptors": ["hotel confirmation UI"],
  "candidateCollections": [
    { "title": "Japan Trip", "confidence": 0.82, "reasonSignals": ["tokyo", "hotel"] }
  ],
  "proposedNewCollection": {
    "title": "Visa Application",
    "emoji": "🛂",
    "confidence": 0.89
  }
}
```

Exact Swift types may vary; validation + bounds required.

---

## Persistence (additive)

Migration theme: `v6_organization_resolver`  
Dedupe / uniqueness: `v7_dedupe_collections` (merge same `normalized_title`, unique index)  
- organization runs / resolver state / pendingNetwork  
- `resolver_version`, organize lock / correction lock  
- content hash cache keys  
- `context_alias` (internal)  
- facets/entities/summary as needed  
- membership `source=ai|user` + confidence  

---

## DEBUG Resolver Inspector (REQUIRED)

Per screenshot: thumb, OCR availability, resolver state/version, understanding status, candidates + confidences, thresholds, decision (reuse/create/NR), selected Collection, provenance, reason signals, retry/failure.  
DEBUG metrics if practical: processed / reused / created / NR / failed / request counts.

---

## Physical-device checklist

| ID | Case | Expected |
|----|------|----------|
| A | Japan Trip exists → Tokyo hotel shot | **REUSE** Japan Trip |
| B | Strong cluster, no existing context | **CREATE** meaningful Collection |
| C | Ambiguous | **Needs Review** |
| D | Image-only | Multimodal attempt → Collection or NR |
| E | User-created Collection | **No** auto-add |
| F | AI assign → user Move | Correction sticks; no bounce-back |
| G | “Trip to Japan” proposal vs Japan Trip | Reuse canonical; no duplicate |
| H | Kill mid-backlog | Safe resume |
| I | Offline | Manual works; pendingNetwork / retry |
| J | New shot incremental | sync→OCR→resolver→Collection |
| K | Search after auto-file | Still finds OCR |
| L | Large backlog | UI responsive |
| M | Provenance | `ai` vs `user` distinguishable |

---

## Success metrics

correct reuse · correct create · duplicate rate · incorrect filing · NR rate · correction rate · latency · failure rate  

**Trust > coverage.**

---

## Implementation phases

| Phase | Work |
|-------|------|
| 8A | Schema, policy, queue skeleton |
| 8B | Resolver core + fixture/local structured provider |
| 8C | Disclosure + cloud gate + optional HTTP client |
| 8D | OCR → organize wire + backlog drain |
| 8E | DEBUG Inspector |
| 8F | Tests + device checklist + completion report |

---

## STOP after Sprint 8

Build · automated tests · completion report · Inspector · device checklist · **STOP**.  
**Do not start Sprint 9** without explicit approval.
