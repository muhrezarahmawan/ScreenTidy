# ScreenTidy — Product Requirements Document (PRD)

## Product Vision

**ScreenTidy is an AI-powered personal memory organizer** that understands the context and intent behind screenshots, then organizes them the way a thoughtful human assistant would.

It transforms cluttered screenshots into a calm, searchable personal memory — not an AI filing cabinet.

## Product Positioning

| We are | We are not |
|--------|------------|
| A personal memory organizer | A folder / file manager |
| Context- and intent-first | Content-type-first navigation |
| An invisible assistant | A manual organization tool |
| Local-first & privacy-first | A cloud photo library |

**Hero question the AI answers:**  
“What is the most meaningful way to organize this information for the user?”  
— not —  
“Which predefined category does this screenshot belong to?”

## Problem Statement

People save screenshots to remember information, but screenshots quickly become buried in their photo library. Gallery apps organize by time. Traditional organizers (and naive AI folders) organize by file type. People remember **trips, projects, decisions, and intents** — not “Hotels” vs “Receipts.”

## Product Philosophy

ScreenTidy is a **privacy-first, AI-first, local-first** iPhone app.

- Screenshots remain in Apple Photos.
- ScreenTidy stores **metadata only** (OCR, Collections / internal Context Collections, Type Facets, Entities, user preferences).
- AI should feel invisible; organization happens automatically and calmly.
- No accounts, no cloud sync, no collaboration, no social features in MVP.

## Official Organization Model (Option C)

### Collections (Primary — user-facing)
User-visible living contexts — the Home experience. Internal domain type: `ContextCollection`.

Examples: Japan Trip, Visa Application, Apartment Setup, Product Research, Qatar Airways, Weekend Restaurants.

**Rules:**
- Always prefer **reusing** an existing Collection before creating a new one.
- Create a new collection only when confidence is high and no suitable collection exists.
- Collections below a configurable membership threshold (default **3**) do **not** appear on Home until they grow or the user **pins** them.
- Users can rename, merge, pin, archive, and manually organize.
- **MVP manual controls (lightweight):** create collection (name + emoji), rename / change emoji, delete collection (collection-only vs collection & screenshots), multi-select move/delete within a collection. Automatic organization into Collections is always on; manual tools correct and personalize — not a file manager.
- AI minimizes unnecessary reorganization to preserve trust.

### Type Facets (Secondary)
Stable content-type metadata — **not** primary navigation.

Examples: Receipt, Flight, Hotel, QR Code, Chat, Document, Invoice, Boarding Pass.

Used for: search, cleanup, filters, explainability, AI reasoning.

### Entities
Extracted when possible: cities, airlines, hotels, merchants, brands, countries, restaurants, companies.

Enrich search and future AI capabilities. May inspire Collection names but are not required to be collections themselves in MVP.

### Needs Review (user-facing; internal Unassigned)
Low confidence → **Needs Review** inbox (internal `kind = unassigned`).  
Never invent an uncertain Collection. Never silently dump into a generic “Other” folder as a substitute for judgment.
Never use “Unassigned” in UI copy.

## Goals
- Automatically organize screenshots by **context and intent**.
- Help users find memories in seconds.
- Feel like an assistant organized their life — not like they manage folders.
- Remain calm, native, private, and local-first.

## MVP Features
1. **Automatic Screenshot Sync** — index screenshots from Apple Photos (metadata only).
2. **AI Memory Organization** — Collections (reuse-first) + Type Facets + Entities (always on; no user toggle).
3. **Home of Collections** — collage-led Collection pockets (not type folders) + Needs Review when needed.
4. **Search** — magical local search over OCR, visual, Collection names, facets, entities, keywords.
5. **Manual Override** — create/rename/emoji; dual delete collection; select → move (+ new collection) / delete screenshots; pin/archive/merge as available.
6. **Cleanup Suggestions** — Duplicates + Old only; reversible; never auto-delete; dual delete paths.

## Explicit Non-Goals (MVP)
- Android / iPad-first
- Auth / accounts / cloud library sync / collaboration / social
- Widgets / AI chat
- Vector semantic search as primary system (roadmap)
- Unconstrained collection churn (re-cluster entire library every launch)
- Type Facets as the primary Home navigation
- Analytics SDKs / monetization / RevenueCat

## Target Users
- Travelers, professionals, students, shoppers, anyone with hundreds of screenshots who thinks in projects and life contexts

## Success Metrics (Qualitative / TestFlight for MVP)
- Successful first import during onboarding
- Users find a known memory within ~10 seconds in moderated tests
- Users describe organization as “my trip / my project,” not “folders”
- Low desire to constantly rename/fix AI contexts
- Trust in cleanup (no accidental Photos deletes)

## Product Principles
1. **Memory First** — organize by meaning, context, and intent.
2. **Assistant Discipline** — reuse before create; don’t thrash.
3. **AI First, Invisible** — the app organizes; the user steers.
4. **Privacy First** — least data leaving the device; ephemeral cloud only.
5. **Local First** — Photos + on-device metadata are the system of record.
6. **Native & Minimal** — screenshots are the hero; chrome stays quiet.
7. **Reversible Cleanup** — suggestions never destroy; Photos delete is explicit.

## Future Roadmap (Post-MVP)
- Stronger entity graphs & Trip/Project timelines
- Semantic search
- AI chat over memories
- Smart reminders / actions
- Cross-device sync
- Monetization & privacy-reviewed analytics

## Document Status
Implementation-ready product contract under **Option C**. Supersedes fixed-taxonomy-as-primary-navigation assumptions.
