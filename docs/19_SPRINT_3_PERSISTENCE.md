# Sprint 3 — Local Persistence

**Status:** **CLOSED / ACCEPTED**  
**Date:** 2026-08-08  
**Scope:** SQLite/GRDB system of record behind Sprint 2 protocols. No PhotoKit, OCR, networking, or UX redesign.

---

## Decision

| Choice | Detail |
|--------|--------|
| Engine | **GRDB 7** (`https://github.com/groue/GRDB.swift.git`) |
| File | Application Support / `ScreenTidy/screentidy.sqlite` |
| Access | `DatabasePool` + foreign keys ON |
| UI contract | Sprint 2 UX unchanged |
| DI | `AppDependencies.memoryStore: any MemoryRepository` → `GRDBMemoryRepository` |

---

## Source of truth

1. **SQLite** owns Collections, screenshot **metadata**, memberships, mock duplicate groups, seed flags.  
2. **Photos** still owns image bytes (unchanged; Sprint 4).  
3. Feature ViewModels continue to depend on **protocols**, not GRDB types.  
4. `MockMemoryStore` remains for Previews / comparison; production DI uses GRDB.

---

## Schema (migration `v1`)

### `screenshot`
Metadata only — no image blobs. Includes `photos_local_identifier` (nullable, Sprint 4), dates, favorite, analysis status, soft-remove flags, `preview_symbol`, and JSON arrays for facet/entity/visual/semantic fields used by mock Search.

### `context_collection`
Collections + Needs Review singleton (`kind = unassigned`, unique partial index). Title, emoji, pin/archive, created/updated, `created_by`.

### `screenshot_context`
Many-to-many membership (`screenshot_id`, `collection_id`) with source/confidence/position. Multi-collection membership supported.

### `duplicate_group`
Persists Sprint 2 mock cleanup groups across relaunch (detection still mock).

### `app_meta`
Key/value: `fixtureSeeded`, `seedVersion`.

### `screenshot_fts` (FTS5)
Virtual table foundation (`screenshot_id`, `ocr_text`, `title_blob`). **Not** populated for production Search in Sprint 3 — reserved for Sprint 5/6.

---

## Migrations

- `DatabaseMigrator` in `AppDatabase`  
- Versioned migration id: **`v1`**  
- Normal upgrades never erase the DB (`eraseDatabaseOnSchemaChange = false`)  
- DEBUG: Settings → **Reset Database & Reseed** wipes tables and reseeds fixtures  

---

## Repositories

`GRDBMemoryRepository` implements:

- `MemoryRepository` (read/write + undo)  
- `SearchProviding` (Sprint 2 mock scoring over DB rows)  
- `CleanupProviding` (duplicates from table; old from `created_at`)  
- `ScreenshotIngesting` (pull-to-refresh mock ingest)  
- `Organizing` (still unavailable — Sprint 8+)

Queries compute `memberCount` / peek symbols from memberships — not denormalized write-time counts.

---

## Undo

Reversible metadata mutations snapshot JSON of core tables before write; `undo(token:)` restores the snapshot into SQLite. Same `MockUndoToken` surface as Sprint 2. **Not** PhotoKit restore.

Covered: move, delete collection (both paths), mock screenshot remove.

---

## Seed strategy

- Stable fixture UUIDs via `FixtureIDs` (deterministic).  
- First empty DB launch: seed Japan Trip, Apartment Setup, Qatar Airways, Visa Application, Weekend Restaurants, Needs Review + screenshots/memberships/duplicates.  
- `fixtureSeeded=1` prevents re-seed after user edits.  
- DEBUG: **Reset Database & Reseed**  

---

## Deferred (not Sprint 3)

- PhotoKit identifiers / real import  
- Production OCR → FTS population / ranking  
- Embeddings / network AI  
- Real duplicate / old detection  
- Rebuild Library  
- Facet vocabulary / OrganizationRun tables (schema can expand in later migrations)

---

## Verification

- App build succeeds with GRDB.  
- Repository unit tests (`ScreenTidyTests`).  
- Manual: create/rename/move/delete → kill app → relaunch → state intact.  

---

## Files

```
Data/Persistence/AppDatabase.swift
Data/Persistence/PersistenceRecords.swift
Data/Persistence/GRDBMemoryRepository.swift
Data/Persistence/DatabaseSeeder.swift
ScreenTidyTests/GRDBMemoryRepositoryTests.swift
```
