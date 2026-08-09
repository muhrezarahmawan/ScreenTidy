# ScreenTidy — Data Model (MVP)

## Principles
- Photos owns image bytes.  
- Local SQLite owns organization memory (contexts, facets, entities).  
- No cloud library database.  
- Context Collections are dynamic titles with stable UUIDs (not fixed taxonomy keys as primary IA).  
- Type Facets use stable keys in a versioned vocabulary.

---

## Entities

### Screenshot
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK |
| photosLocalIdentifier | String | Unique |
| createdAt | Date? | Asset date |
| importedAt | Date | |
| isFavorite | Bool | App-level (MVP) |
| ocrText | String? | |
| ocrLanguage | String? | |
| aiSummary | String? | |
| contentHash | String? | Classify cache |
| photosRevision | String? | Invalidate cache |
| analysisStatus | Enum | `pendingOCR`, `pendingOrganize`, `ready`, `failed`, `excluded` |
| lastError | String? | |
| isRemovedFromApp | Bool | Soft-remove |
| removedAt | Date? | Undo / purge |
| perceptualHash | String? | Near-duplicates |
| eventEndDate | Date? | Expiry signal |
| width / height | Int? | |

### ContextCollection
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | PK — stable identity |
| kind | Enum | `ai_context`, `user_context`, `unassigned` |
| displayTitle | String | User-renamable |
| normalizedTitle | String | For matching / reuse |
| isPinned | Bool | |
| pinOrder | Int? | |
| isArchived | Bool | Hidden from Home |
| createdAt | Date | |
| updatedAt | Date | |
| lastActivityAt | Date? | Home ranking |
| createdBy | Enum | `ai`, `user` |

**Constraints:** At most one row with `kind = unassigned`.

### ContextAlias
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| collectionId | UUID | Surviving collection after merge/rename |
| aliasTitle | String | Prior titles / AI variants for reuse matching |
| normalizedAlias | String | |

### ScreenshotContext (membership)
| Field | Type | Notes |
|-------|------|-------|
| screenshotId | UUID | |
| collectionId | UUID | |
| source | Enum | `ai`, `user` |
| confidence | Double? | |
| createdAt | Date | |

Unique (`screenshotId`, `collectionId`). Multi-context membership allowed.

### TypeFacetDef
| Field | Type | Notes |
|-------|------|-------|
| stableKey | String | PK e.g. `receipt`, `flight` |
| displayName | String | |
| vocabularyVersion | Int | |

### ScreenshotFacet
| Field | Type | Notes |
|-------|------|-------|
| screenshotId | UUID | |
| facetKey | String | FK to TypeFacetDef |
| confidence | Double? | |
| source | Enum | `ai`, `user` |

### Entity
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| screenshotId | UUID | |
| type | Enum | `city`, `airline`, `hotel`, `merchant`, `brand`, `country`, `restaurant`, `company`, `other` |
| value | String | |
| normalizedValue | String | |
| confidence | Double? | |

### OrganizationRun
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| screenshotId | UUID | |
| startedAt / finishedAt | Date | |
| provider | String | |
| status | Enum | `success`, `failure`, `skippedOffline`, `skippedNoConsent` |
| requestFingerprint | String | |
| rawResponseDigest | String? | Hash only |

### CleanupOverview / DuplicateGroup (MVP UI)
| Type | Notes |
|------|-------|
| CleanupOverview | duplicateScreenshotCount, duplicateGroupCount, oldScreenshotCount, oldThresholdMonths (default 6) |
| DuplicateGroup | screenshotIDs[], recommendedKeepID? (future keep-one UX) |

### CleanupSuggestion (legacy / future pipeline)
| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| screenshotId | UUID | |
| category | Enum | MVP: `duplicate`, `old` only — **`expired` removed** (not in product) |
| reason | String | |
| score | Double | |
| duplicateGroupId | UUID? | |
| status | Enum | `active`, `dismissed`, `resolved` |
| createdAt | Date | |

### AppSettings (singleton)
| Field | Type | Notes |
|-------|------|-------|
| cloudAIConsent | Bool | **Superseded for UI** — organization always on (D-032); may remain for future privacy gateway |
| cloudAIEnabled | Bool | **Superseded for UI** — no Settings toggle |
| oldScreenshotDays | Int | Default **180** |
| homePromotionThreshold | Int | Default **3** |
| onboardingCompleted | Bool | |
| facetVocabularyVersion | Int | |
| organizationPromptVersion | String? | Cache busting |

---

## Full-Text Search (FTS5)

`screenshot_fts` columns:
- ocrText  
- contextTitlesConcat  
- facetLabelsConcat  
- entitiesConcat  
- keywordsConcat  
- aiSummary  

Keep synchronized on OCR, organization, rename, merge, membership changes.

---

## Derived / Cache
- Thumbnails by `photosLocalIdentifier` + revision  
- Collage picks per Context Collection  

---

## Deletion Semantics

### Remove from ScreenTidy
Soft-delete + **Undo** window (e.g. 30 days), then purge. Photos untouched. Soft-removed excluded from search/Home.

### Delete from Apple Photos
Explicit confirm → Photos API → on success hard-remove local rows. Not app-undoable after system confirm.

### Photos asset removed externally
Observer reconciles; drop or flag local row.

### Merge Context Collections
- Move memberships to target  
- Write aliases from source titles  
- Archive or delete source row  
- Do not delete screenshots  

### Archive Context Collection
`isArchived = true` — hidden from Home; searchable; restorable.

---

## Needs Review (internal: Unassigned)
Seeded singleton Context Collection `kind = unassigned`.  
**User-facing display title: Needs Review** (never “Unassigned” in UI).  
AI low confidence assigns here. User reassignment removes Needs Review membership.

---

## Home Promotion
A non-unassigned, non-archived Context Collection appears on Home if:
`isPinned OR memberCount >= homePromotionThreshold`

---

## Migration Posture
Local schema versioning from day one. Facet vocabulary and prompt versions migrate independently of context UUIDs.
