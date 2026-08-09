# ScreenTidy — Documentation Index

Single source of truth for MVP. Read in order when onboarding to the project.

| Doc | Purpose |
|-----|---------|
| [00_ARCHITECTURE.md](00_ARCHITECTURE.md) | Architecture decisions & approval checklist |
| [01_PRD.md](01_PRD.md) | Product vision, scope, principles |
| [02_UX_SPEC.md](02_UX_SPEC.md) | UX flows, screens, states |
| [03_TECH_SPEC.md](03_TECH_SPEC.md) | Technical specification |
| [04_VISUAL_DIRECTION.md](04_VISUAL_DIRECTION.md) | Visual north star |
| [05_INFORMATION_ARCHITECTURE.md](05_INFORMATION_ARCHITECTURE.md) | Navigation & object model |
| [06_DATA_MODEL.md](06_DATA_MODEL.md) | Local schema & deletion semantics |
| [07_AI_PIPELINE.md](07_AI_PIPELINE.md) | OCR + hybrid organization pipeline |
| [08_PRIVACY_SECURITY.md](08_PRIVACY_SECURITY.md) | Privacy promise & threats |
| [09_PERMISSIONS_AND_SYNC.md](09_PERMISSIONS_AND_SYNC.md) | Photos access & sync |
| [10_DESIGN_SYSTEM.md](10_DESIGN_SYSTEM.md) | Tokens & components |
| [11_ACCEPTANCE_CRITERIA.md](11_ACCEPTANCE_CRITERIA.md) | MVP done-when checklist |
| [12_OPEN_QUESTIONS.md](12_OPEN_QUESTIONS.md) | Unresolved decisions |
| [13_IMPLEMENTATION_ROADMAP.md](13_IMPLEMENTATION_ROADMAP.md) | Sprint roadmap → TestFlight |
| [14_WORKING_AGREEMENT.md](14_WORKING_AGREEMENT.md) | Collaboration & quality rules |
| [15_SPRINT_0_NOTES.md](15_SPRINT_0_NOTES.md) | Sprint 0 completion notes |
| [16_HOME_DIRECTION_EXPLORATION.md](16_HOME_DIRECTION_EXPLORATION.md) | Home direction (Quiet Pocket locked) |
| [17_SPRINT_1_DESIGN_SYSTEM.md](17_SPRINT_1_DESIGN_SYSTEM.md) | Sprint 1 Design System delivery |
| [18_SPRINT_1_SESSION_PAUSE.md](18_SPRINT_1_SESSION_PAUSE.md) | Sprint 1 pause / resume checklist |
| [19_SPRINT_3_PERSISTENCE.md](19_SPRINT_3_PERSISTENCE.md) | Sprint 3 GRDB/SQLite persistence |
| [20_SPRINT_4_PHOTOS.md](20_SPRINT_4_PHOTOS.md) | Sprint 4 PhotoKit READ/SYNC — **CLOSED / ACCEPTED** |
| [21_SPRINT_5_OCR.md](21_SPRINT_5_OCR.md) | Sprint 5 on-device OCR foundation — **CLOSED / ACCEPTED** |
| [22_SPRINT_6_SEARCH.md](22_SPRINT_6_SEARCH.md) | Sprint 6 Search (FTS wired) — **CLOSED / ACCEPTED** |
| [23_SPRINT_7_MANUAL_ORGANIZATION.md](23_SPRINT_7_MANUAL_ORGANIZATION.md) | Sprint 7 Manual Memory Organization — **CLOSED / ACCEPTED** |
| [24_SPRINT_8_COLLECTION_RESOLVER.md](24_SPRINT_8_COLLECTION_RESOLVER.md) | Sprint 8 Collection Resolver — **OPEN (product-quality gate; Architecture C)** |
| [25_RAILWAY_GATEWAY.md](25_RAILWAY_GATEWAY.md) | Hosted HTTPS gateway on Railway (**P0**) |

Project journal (sprint reviews + decision log): [`../reviews/`](../reviews/README.md)

## Canonical mental model

**ScreenTidy is an AI-powered personal memory organizer** that understands the context and intent behind screenshots, then organizes them the way a thoughtful human assistant would.

| Term | Meaning |
|------|---------|
| **Collection** / **Collections** | **User-facing** primary Home unit (Japan Trip, Visa Application). Never say “Context Collections” in UI. |
| **Context Collection** | Internal/domain name (`ContextCollection`). Docs may use it for architecture. |
| **Type Facet** | Secondary type metadata (Receipt, Flight, Chat…) for search, cleanup, filters — **not** Home folders. |
| **Entity** | Extracted names (airlines, cities, merchants…) enriching search / future AI. |
| **Unassigned** | Internal low-confidence inbox (`kind=unassigned`). **User-facing: Needs Review.** Never invent uncertain contexts. |
| **Needs Review** | User-facing label for Unassigned. Home card only when non-empty. |
| **Collection Resolver** | On-device logic: reuse / create / Unassigned / Home promotion. |
| **Organize** | Preferred verb for organization work (user-facing). Prefer over “classify” / “AI organization.” |

## Architecture stance (one paragraph)

ScreenTidy is a local-first iPhone app (iOS 17+): Apple Photos holds screenshot bytes; SQLite+FTS5 holds organization data and search; Apple Vision performs OCR; optional ephemeral cloud multimodal AI proposes Collections (reuse-first), Type Facets, and Entities; an on-device resolver applies assistant discipline. No auth, no library sync, no analytics/IAP in MVP. Home shows **Collections**, not folders. UI copy says Collections — not “Context Collections.”
