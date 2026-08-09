# ScreenTidy — Information Architecture

## Mental Model

ScreenTidy organizes **memories by context and intent**.

| Concept | User-visible? | Role |
|---------|---------------|------|
| **Collection** / **Collections** | Yes — primary Home | Living context (Japan Trip, Visa Application). Internal type: `ContextCollection`. |
| **Type Facet** | Secondary (search / future filters) | Stable type (Receipt, Flight, Chat…) — **not** Home cards; not shown as document chrome on screenshots |
| **Entity** | Secondary (search signals) | Airline, city, merchant… — internal for organization/search |
| **Needs Review** | Yes — review inbox when non-empty | Low-confidence items. Internal `kind = unassigned`. Never say “Unassigned” in UI. |
| **Custom Collection** | Yes | User-created Collection; AI does not auto-file into it unless user places items (MVP) |

There is **no** primary fixed taxonomy of Home folders.

---

## Navigation Model

### Tabs
| Tab | Role |
|-----|------|
| Home | Collections + Needs Review (when needed) |
| Search | Real-time find across OCR, visual, Collections, semantic signals |
| Cleanup | Duplicates + Old Screenshots |
| Settings | Photos status, About, Developer |

```
Onboarding → Main Tabs
               ├─ Home → Collection Detail → Screenshot Viewer
               ├─ Search → Screenshot Viewer
               ├─ Cleanup → Screenshot Viewer
               └─ Settings
```

Sheets: Rename/Emoji, New Collection, Move picker, dual Delete Collection, Delete screenshots.

---

## Object Model

### Screenshot
Photos-backed asset + local metadata (OCR, facets, entities, memberships, favorite, hashes, dates).  
**UI:** the screenshot image is the primary object — no title/description/OCR blocks in gallery or viewer.

### Collection (internal: Context Collection)
- `kind`: `ai_context` | `user_context` | `unassigned`  
- Display title (renamable); user-facing name is always **Collection**  
- Pin / archive / merge support  
- Multi-screenshot membership (a screenshot may belong to **multiple** Collections)  
- Home visibility governed by **promotion threshold** (default 3) unless pinned / user-created  

### Type Facet
Closed, versioned vocabulary of content types. Many facets per screenshot allowed. Not Home cards.

**MVP facet set (versioned, extensible):**  
Receipt, Flight, Hotel, QR Code, Chat, Document, Invoice, Boarding Pass, Shopping, Restaurant, Meme, Study Note, Other Type  

> Facets support reasoning/cleanup/search. Exact list may be tuned; they must remain secondary to Collections.

### Entity
Typed string values (city, airline, hotel, merchant, brand, country, restaurant, company, other). Indexed for search.

### Cleanup (MVP)
Categories exposed in UI: **duplicate**, **old** only.  
(Expired / flight-date cleanup is **not** in MVP.)

---

## Home Composition Rules

1. **Needs Review** when count > 0 (compact card; never zero-count)  
2. **Pinned** Collections (user order)  
3. **Promoted** Collections — member count ≥ threshold (default 3), not archived; user-created always eligible  
4. Order remaining by recent activity  
5. Below-threshold AI contexts: hidden from Home (still exist; findable in Search)  
6. **New Collection** tile as last grid cell  
7. Type Facets never appear as primary Home collection cards  
8. No Home search field; no cleanup teaser on Home (Cleanup tab owns that)

---

## Search IA

- Real-time local query (debounced) across OCR · visual labels · Collection titles · semantic keywords · (date hooks later)  
- Results: Collections (strong title matches) + 3-column screenshot grid  
- Zero-query: calm ready state + suggestion chips  
- Viewer gallery = current result set  
- Filters (Collection / Facet / Favorites): later polish  

---

## Cleanup IA

1. Duplicates (perceptual hash)  
2. Old (default 6 months)  

Actions: multi-select · confirm · mock delete with Undo (Sprint 2). PhotoKit delete later.

---

## Settings IA

Photos (mock status) · About · Developer (Replay Onboarding; DEBUG Empty Library Onboarding)  
Organization is always on — no AI toggle.  
Rebuild Library deferred until real indexing exists.

## Trust Moments

| Moment | Placement |
|--------|-----------|
| Photos access | Onboarding + Settings status |
| Ephemeral AI / privacy | Later product copy; organization always on |
| Delete from Photos | Detail + Cleanup (confirm) |

---

## Non-structures (MVP)
- No account graph / sharing  
- No nested folder trees as primary IA  
- No type-taxonomy Home  
- No AI chat surface  
- No “Context Collections” / “Unassigned” / AI organization toggle in UI  
