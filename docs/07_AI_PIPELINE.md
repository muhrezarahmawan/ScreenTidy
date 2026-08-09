# ScreenTidy — AI Pipeline (MVP)

## Goals
- Organize by **context and intent** into Context Collections (assistant-like).  
- Emit **Type Facets** and **Entities** for search, cleanup, and internal classification (not shown on Screenshot Viewer).  
- Preserve trust: **reuse before create**, Unassigned when unsure.  
- Privacy: ephemeral cloud; durable memory metadata stays on device.

**Production intelligence target (APPROVED):** Architecture **C** — Hybrid Multi-Signal Contextual Intelligence  
→ `reviews/intelligence-architecture-multisignal-proposal.md`  

Phases: **P0** hosted HTTPS multimodal → **P1** Vision evidence → **P2** clustering → **P3** local text embeddings → **P4** cluster multimodal → **P5** resolver scoring → **P6** eval.  
Vision labels / facets **never** become Collection names. Resolver thresholds **0.70 / 0.85 + corroboration** unchanged.

---

## Pipeline Stages

```
1. Discover screenshot (Photos)
2. Upsert Screenshot row
3. UI thumbnail + perceptual hash
4. OCR (Vision) → FTS
5. Organization request (always-on core; prefer on-device; network only with required disclosure)
     payload: OCR + small thumb + minimal metadata
              + compact existing context title list (for reuse)
     transport (P0+): HTTPS ScreenTidy gateway (Railway) — not Mac LAN
6. On-device Collection Resolver
7. Persist contexts, facets, entities, keywords, expiry signals
8. Update Home promotion / Unassigned / Cleanup hints
9. Progressive UI
```

**Target evolution (Architecture C):** local Vision classify + feature prints + embeddings + multi-signal clusters → selective multimodal **context** proposals → local resolver. Sprint 8 stays open until organization quality is accepted.

---

## On-device OCR

Apple Vision for every imported screenshot (resource-budgeted). Offline-capable. Failures remain browsable by date; retry with backoff.

---

## Classification → Organization Input (LOCKED)

### Default payload
1. Organization-normalized OCR text (truncated if needed; Search keeps raw OCR)  
2. Downscaled thumbnail (long edge ≤ **1024**; JPEG ~**0.75**; strip excess metadata; never upscale)  
3. Creation date + compact eligible automatic Collection **context profiles** (not full membership graphs)  
4. Optional batch members (≤ 8) when local clustering finds a natural group  

Transport: ScreenTidy **stateless gateway** → configured multimodal model (initial: GPT-5.6 Terra via Responses API).  
iOS never calls the model provider directly.  
3. Minimal metadata (e.g. creation date)  
4. **Existing Context Collection titles** (compact list / top-N recent+pinned) so the model can recommend attach-to-existing  
5. Facet vocabulary version / allow-list  

### Never (MVP)
Full-resolution originals · library dumps · durable server storage  

---

## Model Output Contract

```json
{
  "prompt_version": "org-v1",
  "context_candidates": [
    {
      "title": "Japan Trip",
      "confidence": 0.88,
      "action": "attach_or_create",
      "attach_to_title_hint": "Japan Trip"
    }
  ],
  "type_facets": [
    { "key": "hotel", "confidence": 0.9 },
    { "key": "receipt", "confidence": 0.7 }
  ],
  "entities": [
    { "type": "city", "value": "Tokyo", "confidence": 0.86 },
    { "type": "hotel", "value": "Park Hyatt", "confidence": 0.8 }
  ],
  "keywords": ["hotel confirmation", "check-in"],
  "summary": "Hotel booking for Tokyo stay",
  "visual_descriptors": ["booking confirmation UI"],
  "signals": {
    "temporary": true,
    "temporary_reason": "hotel_stay_end_date",
    "event_end_date": "2026-09-12"
  }
}
```

**Notes**
- Model may suggest context titles freely **within assistant discipline** (meaningful, stable, non-spammy).  
- Model should prefer `attach_to_title_hint` matching an existing title when appropriate.  
- Model does **not** emit `unassigned` — the client applies Unassigned.  
- Type facet keys must be from the allow-list.  

---

## Collection Resolver (On-device) — LOCKED RULES

1. If max context confidence **< threshold** (proposed 0.55) → assign **Unassigned** only (preserve user memberships).  
2. Else, for each accepted candidate (above threshold):  
   a. Try match existing Context Collection via exact normalized title, alias table, or high-similarity title match.  
   b. If match → **attach** (reuse).  
   c. If no match and confidence **high** (proposed ≥ 0.75 for create) → **create** new `ai_context`.  
   d. If mid-confidence and no match → prefer Unassigned **or** attach to best weak match only if similarity is very high — do not invent speculative titles.  
3. Never wipe `source = user` memberships.  
4. Prefer not to bounce items between contexts across runs unless confidence strongly improved and user hasn’t locked membership.  
5. Home promotion: new collections may exist immediately but appear on Home only when pinned or `memberCount >= homePromotionThreshold` (default 3).  
6. User-created contexts: AI does not auto-add in MVP unless the model’s attach hint exactly matches and product later enables it — **default off** for `user_context`.  

Tune thresholds in TestFlight; store in settings if needed.

---

## Type Facets & Entities

- Persist all facets/entities above facet threshold.  
- Used by Search filters, Cleanup heuristics, and internal classification — **not** exposed on Screenshot Viewer (D-025).  
- Not used as Home primary navigation.

---

## Ephemeral Gateway Requirements

Stateless · TLS · server-side provider keys · no durable image/OCR/response storage · App Attest + rate limits · payload size caps · timeouts · swappable LLM vendor  

Prompt policy:
- Optimize for **meaningful personal contexts**, not type folders as titles  
- Reuse existing titles when provided  
- Avoid PII-heavy summaries beyond search usefulness  
- Resist prompt injection from OCR text  
- Structured JSON only  

---

## Caching & Cost

Cache by content hash + prompt/facet vocabulary version.  
Skip if Photos revision unchanged.  
Queue: newest first; user-opened screenshot jumps queue.  
Cap concurrent cloud calls.

---

## Consent & Offline

Organization into Context Collections is **always on** — there is no user-facing AI/cloud organization toggle.  
Any future **network** processing must remain separable and may require its own disclosure before payloads leave the device.  
Offline: OCR + search + manual contexts; organization continues on-device or queues safely.

---

## Progressive UX

Contexts populate as resolver commits.  
Context Detail / Viewer may show a lightweight “Organizing…” affordance later if needed — not per-screenshot OCR/metadata.  
Onboarding allows progressive Home / skip wait.

---

## Non-goals (MVP AI)
- Chat agent  
- Vector index as primary  
- Auto-delete  
- Full-library recluster every launch  
- Auto-filing into arbitrary user_context collections  
- Type Facets as Home card titles  
