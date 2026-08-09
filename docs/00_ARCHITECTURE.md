# ScreenTidy — Architecture Decisions (MVP)

Status: **Approved — Option C (Personal Memory Organizer)**  
Related: `01_PRD.md`, `03_TECH_SPEC.md`, `05_INFORMATION_ARCHITECTURE.md`, `07_AI_PIPELINE.md`

---

## Product philosophy (locked)

> ScreenTidy is an AI-powered personal memory organizer that understands the context and intent behind screenshots, then organizes them the way a thoughtful human assistant would.

Home presents **Context Collections**, not type folders.

---

## 1. System Shape

```
┌──────────────────────────────────────────────────────────┐
│                    iPhone (Source of Truth)               │
│  Apple Photos     ← screenshot bytes                     │
│  SQLite + FTS5    ← metadata, contexts, facets, search   │
│  Vision OCR       ← text extraction                      │
│  Collection Resolver ← reuse / create / Unassigned       │
│  SwiftUI App      ← memory-first UX                      │
└────────────────────────────┬─────────────────────────────┘
                             │ ephemeral HTTPS (optional)
                             ▼
                 ┌─────────────────────────┐
                 │ Stateless AI Gateway    │
                 │ (no user DB, no store)  │
                 └─────────────┬───────────┘
                               ▼
                       Vision-capable LLM
```

**Non-negotiables**
- No auth / no cloud library sync / no permanent server image storage
- Screenshots never copied into an app-owned media vault
- Minimum iOS **17+**
- Context Collections are primary UI; Type Facets are secondary metadata

---

## 2. Decision: Option C organization model — **LOCKED**

| Layer | Role |
|-------|------|
| **Context Collections** | Primary Home — dynamic, reuse-first, user-steerable |
| **Type Facets** | Stable type metadata for search/cleanup/filters/explainability |
| **Entities** | Extracted names for search & future AI |
| **Unassigned** | Low-confidence review — no invented uncertain contexts |

**Rejected**
- **Option A** as primary: fixed taxonomy Home (feels like AI folders)
- **Option B** unconstrained: free naming without reuse/merge/min-size discipline (chaos)

---

## 3. Decision: Local-first metadata — **LOCKED**

SQLite + FTS5 via **GRDB**. Performance and search quality over ORM convenience.

**Sprint 0:** GRDB package intentionally not linked; add in Sprint 3 (`docs/15_SPRINT_0_NOTES.md`).

---

## 4. Decision: Hybrid AI — **LOCKED**

On-device OCR + ephemeral cloud multimodal analysis.

**Payload:** OCR text + small thumbnail + minimal metadata. Never full-resolution by default. No permanent server storage.

**Outputs:** context proposals (with reuse hints), type facets, entities, keywords, optional expiry signals.

**Client:** `OrganizationService` / resolver prefers existing Context Collections; applies Home promotion threshold; writes Unassigned on low confidence.

---

## 5. Decision: No Supabase app backend — **LOCKED**

Stateless AI gateway only.

---

## 6. Decision: Search = local enhanced lexical (FTS5) — **LOCKED**

Index OCR + Context Collection titles + facets + entities + keywords. Semantic/vector search post-MVP.

---

## 7. Decision: Cleanup — **LOCKED**

| Rule | Value |
|------|--------|
| Old | **6 months** default (configurable later) |
| Duplicates | **Perceptual hash** |
| Time-bound / expired | AI dates when possible + heuristics + facets (e.g. boarding pass) |
| Auto-delete | **Never** |
| Photos delete | Always explicit confirmation |
| Remove from app | Undo via soft-delete where practical |

---

## 8. Decision: Dual delete — **LOCKED**

Remove from ScreenTidy ≠ Delete from Apple Photos.

---

## 9. Decision: No analytics / monetization in MVP — **LOCKED**

---

## 10. Context Collection discipline (product + eng contract)

1. **Reuse before create**
2. **High confidence** required to mint a new Context Collection
3. **Home promotion threshold** (default 3 members) unless pinned
4. User: rename, merge, pin, archive, manual membership
5. **Minimize reorganization** — no full-library reshuffle on every launch
6. Low confidence → **Unassigned**

---

## 11. Abuse & cost controls

App Attest/DeviceCheck, rate limits, payload caps, client cache by content hash + model/prompt version.

---

## 12. Build sequence

1. Photos import + SQLite + thumbnails  
2. OCR + FTS  
3. Manual Context Collections + Unassigned + facets schema  
4. Ephemeral AI + collection resolver (reuse-first)  
5. Cleanup  
6. Polish: collages, merge UX, onboarding, motion  

---

## Approval Checklist

- [x] Option C memory-organizer philosophy
- [x] Context Collections primary; Type Facets secondary
- [x] Entities for search enrichment
- [x] Unassigned for low confidence
- [x] Reuse-before-create + Home threshold
- [x] Hybrid ephemeral AI + SQLite/FTS + iOS 17+
- [x] Dual delete + cleanup defaults
- [x] No auth / analytics / IAP in MVP
