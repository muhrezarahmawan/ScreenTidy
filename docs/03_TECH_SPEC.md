# ScreenTidy — Technical Specification

## Architecture Summary (MVP)

ScreenTidy is a **local-first personal memory organizer** for iPhone:

| Concern | MVP approach |
|---------|----------------|
| Screenshot bytes | Apple Photos |
| Metadata | **SQLite + FTS5** (contexts, facets, entities, memberships) |
| OCR | On-device Apple Vision |
| Organization AI | **Hybrid** — ephemeral cloud multimodal + on-device **Collection Resolver** |
| Primary UX model | **Context Collections** (dynamic, reuse-first) |
| Secondary model | **Type Facets** + **Entities** |
| Search | Local FTS over OCR + context titles + facets + entities + keywords |
| Minimum iOS | **17+** |
| Auth / sync / analytics / IAP | None |

See `00_ARCHITECTURE.md`, `07_AI_PIPELINE.md`, `06_DATA_MODEL.md`.

---

## Organization Architecture (Option C)

```
Screenshot
  → OCR (on-device)
  → FTS index update
  → Ephemeral AI analysis (optional)
       → context_candidates[]  (titles + confidence + attach hints)
       → type_facets[]
       → entities[]
       → keywords / summary / expiry signals
  → Collection Resolver (on-device)
       → reuse existing Context Collection (similarity / alias)
       → or create new (high confidence only)
       → or Unassigned (low confidence)
       → apply Home promotion threshold
  → Persist memberships + facets + entities
```

**Resolver principles**
1. Reuse before create  
2. Never mint low-confidence context titles  
3. Minimize membership churn after user edits  
4. User merges/renames are honored going forward (alias table)

---

## Hybrid AI (locked)

| On-device | Ephemeral cloud |
|----------|-----------------|
| OCR, thumbnails, FTS, resolver, pHash, UI | Context proposals, facets, entities, keywords, date signals |

**Payload:** OCR + small thumbnail + minimal metadata (+ compact list of existing context titles for reuse).  
**Never:** full-resolution originals by default; durable server storage.

If offline / no consent: browse + OCR search + manual contexts work; AI organization queues.

---

## Search Architecture

**Local Enhanced Lexical Search (FTS5)** over:
- OCR text  
- Context Collection display titles (+ aliases)  
- Type Facet labels  
- Entity values  
- Keywords / short summaries  

Ranking boosts: favorites, exact context title match, entity hit, recency.  
Type-folder browse is **not** the search backbone — memory titles and text are.

Semantic/vector search: post-MVP.

---

## Tech Stack

### Client
- SwiftUI  
- Photos + Vision  
- SQLite + FTS5 (GRDB or equivalent)  
- Background tasks as available  

### Server
- Stateless ephemeral AI gateway only  
- No Supabase user DB, no auth  

### Deferred
- RevenueCat, Firebase, sync, accounts  

---

## Logical Modules
- PhotosImportService  
- OCRService  
- OrganizationService (gateway client)  
- CollectionResolver (reuse / create / Unassigned / promotion)  
- EntityStore / FacetStore  
- SearchService (FTS)  
- CleanupService  
- ThumbnailCache + PerceptualHashService  
- PrivacyConsentStore  

---

## Performance Goals
- 10,000+ screenshots indexed  
- Smooth grids via thumbnail cache  
- Incremental import; non-blocking organization queue  
- Collages from cached thumbs  
- Resolver must be cheap locally (string/alias match first; optional embedding later)

---

## Security & Privacy
See `08_PRIVACY_SECURITY.md`. Context titles can be sensitive (e.g. Visa Application) — stored on device; ephemeral in flight.

---

## Dependencies
SwiftUI, Photos, Vision, SQLite/FTS5, ephemeral AI gateway. iOS 17+.
