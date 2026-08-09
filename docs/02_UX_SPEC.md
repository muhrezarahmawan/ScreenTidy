# ScreenTidy — UX Specification

## UX Principles
- Feels like a **personal memory organizer**, not a file manager.
- Quietly organizes life into meaningful **Collections**.
- One primary action per screen; calm, spacious, native iOS.
- Assistant discipline is visible in behavior (stable names, rare churn) — not in technical jargon.
- Privacy-visible at permissions and Photos delete.
- Cleanup is suggestive and reversible.

## Terminology (use consistently in UI copy)
| Term | Meaning |
|------|---------|
| **Collection** / **Collections** | **User-facing** name for primary Home groups (e.g. Japan Trip). Never “Context Collections” in UI. |
| Context Collection | **Internal** domain/architecture name only (`ContextCollection`) |
| Type / filter | Type Facet exposed in search/cleanup filters — not Home folders |
| Unassigned | Internal `kind`; **user-facing: Needs Review** |
| Avoid in UI | “Context Collection(s),” “AI organization,” “metadata,” “index,” “classification,” “folder,” “category taxonomy” |

---

## Navigation

### Tabs (floating)
1. **Home** — Collections + Needs Review (when needed)  
2. **Search**  
3. **Cleanup**  
4. **Settings**

### Stack / sheets
- Collection Detail  
- Screenshot Viewer  
- Onboarding  
- Merge Collections  
- Rename / Archive  
- Move / Add to Collection  
- Delete confirmations (dual path)  
- Permission recovery  

Home uses the **Search** tab (floating tab bar) — no duplicate search field on Home.

---

## Onboarding

### Happy path (4 progress stages)
1. **Welcome** — organizes screenshots into Collections; privacy one-liner  
2. **Photos Permission** — Allow / Limited / Don’t Allow  
3. **Import** — gathering screenshots  
4. **Organizing / Complete** — progressive Collections (or friendly empty) → **Home**

Progress UI: minimal dots (1…4). **Photos Permission** and **Denied Recovery** share stage **2**. Indicator is not tappable. Gone on Home.

### User-facing onboarding copy (locked)

**Welcome** — ScreenTidy · Your screenshots, quietly organized. · ScreenTidy automatically organizes your screenshots into Collections for trips, projects, plans, and more. · Your screenshots stay in Photos. ScreenTidy keeps them organized without moving them. · Continue  

**Photos** — Allow access to your screenshots · ScreenTidy uses your screenshots to automatically organize them into Collections. · Reassurance: Screenshots stay in Photos · ScreenTidy only organizes your screenshots · You can change access later in Settings. Do not claim PhotoKit is screenshot-only unless implementation guarantees it.  

**Organizing** — Organizing your screenshots · ScreenTidy is grouping your screenshots into Collections based on what they’re about. · Continue to Home  

### Organization is always on (locked)

Organizing screenshots into **Collections** is **core product** — not an optional preference, not an onboarding toggle, and not a Settings switch.

- Prefer benefit language (“Organizes screenshots into Collections”) over implementation jargon.  
- Architecture may still separate on-device vs future network processing for privacy/disclosure — that is not a user-facing “enable AI” control.  
- Sprint 2 continues mock organization; no real network/AI as part of this decision.

### Organizing step = real library (locked)

The final onboarding screen builds the **same Collections** Home will show — not disposable mock cards.

- Titles, emoji, peeks, counts, and order come from organization (resolver later; mock store in Sprint 2).  
- UI reuses **`ContextCollectionPocketView`** only — same model, layout rules, and rendering as Home.  
- Progressive reveal: empty → first collection → more → import finishes → Home with the **same data**.  
- User is watching ScreenTidy build their real library.

### Photos permission edge cases (locked UX)

**Prerequisite:** Photos access is **mandatory**. ScreenTidy’s core purpose is organizing screenshots into Collections. Without access, the app cannot perform its primary function. Do **not** continue to Home without Photos access (full or limited).

Principles: calm and respectful on denial · clear why access is required · privacy-honest · always a path to enable access · never a “use the app empty” path.

#### 1. Allow Access
Photos Permission → system Photos dialog → granted → Import → Organizing → Home.

#### 2. Limited Photos
Photos Permission → system Limited picker → user selects → Import **only selected** screenshots → Organizing → Home.

- Settings later shows a calm line such as: “Managing 42 selected screenshots.”  
- User can expand selection anytime (no dark patterns).

#### 3. Don’t Allow → recovery (same progress stage 2)
Do **not** force system Settings as the only first response — show an in-app recovery screen first.

Copy:

**Title:** Photos access is required  

**Body:**  
ScreenTidy organizes your screenshots into Collections.  

Without access to your screenshots, ScreenTidy can’t work.  

You can enable Photos access in Settings and return to continue.

**Primary:** Enable Photos Access  
**Secondary:** Exit ScreenTidy  

No “Continue without Photos.” No Home without access.

#### 4. Enable Photos Access (from recovery)
Sprint 2: mock grant → continue to Import.  

Later (real permissions): deep-link to the app’s Settings page. When the user returns:
- access granted → continue onboarding automatically  
- still denied → remain on recovery screen  

#### 5. Exit ScreenTidy
Leaves the app. Onboarding is **not** marked complete. Next launch resumes onboarding (Welcome or Photos stage as appropriate) — user is not stuck on a hollow Home.

#### 6. Enable / expand Photos from Settings (after onboarding completed with access)
Settings → Enable Photos / manage Limited → system permission → granted → start or resume import → organizing → Home updates **without restart**.

#### 7. Permission revoked after onboarding
On next launch / active: detect revoked access · pause organization · **preserve** Collections and on-device organization · show unobtrusive recovery (banner or full-screen gate) with Enable Photos Access. Do **not** wipe Collections. Do **not** pretend the product works without access.

#### 8. Import interrupted (app killed, reboot, etc.)
On next launch, resume where possible. Never restart import from zero when progress exists. *(Real resume: later sprints. Sprint 2: mock state only.)*

#### 9. Zero screenshots found
Import succeeds with 0 items (access was granted) → friendly empty on Home, e.g.:

> No screenshots found.  
> We’ll automatically organize new screenshots as you take them.

#### 10. Library has only non-screenshots
Same as zero screenshots. Explain ScreenTidy focuses on screenshots. Not an error.

### Other onboarding notes
- Offline: OCR local; context AI queues when hybrid is enabled.  
- Copy: memory/context organizer — not folder taxonomy.

---

## Home
Must feel like browsing **life contexts**, not folders.

Locked IA (Quiet Pocket):

```
Good evening 👋

[Approved rotating subtitle from `STHomeCopy` — selected once per Home visit]

Needs Review (if needed)

Collection cards (hero)
```

- Greeting — calm and personal (Good morning / afternoon / evening)  
- Subtitle — rotates from the **approved `STHomeCopy` pool** once per Home visit (stable while viewing; avoid immediate repeat on return). Not AI-generated.  
- **No search field on Home** — Search lives in the floating tab bar  
- **Collections are the hero**  
- **Needs Review** (user-facing name for internal `unassigned`) appears only when count > 0 as a compact soft card between greeting and collections. Never show a zero-count empty state.  
- No dashboard widgets, analytics, or unnecessary sections  

### Needs Review (Home entry + screen)
- User-facing label: **Needs Review** (not “Unassigned”)  
- Home card (**locked compact**): leading 2–3 overlapping screenshot peeks + “[N] screenshots need your help” + “Review where these screenshots belong”  
- **Entire card tappable** — no sparkle icon, no oversized Review CTA  
- Secondary to Collections; no warning colors  
- Detail: same 3-column gallery, Select / Move (+ New Collection) / Delete, fullscreen viewer — no OCR/titles/entities  
- Meaning: ScreenTidy was not confident enough to place these automatically; do not invent speculative collections to avoid review  

### Collection Card (signature)
- Compact soft **folder** — short/wide, dense (not a tall empty card)
- Max **3** large screenshots **tucked inside** (behind the front panel)
- ~**40%** of each screenshot visible above the lip; fan with center highest
- **Emoji** top-left; **title + metadata** bottom-left (~18–20pt left, ~18–24pt bottom); middle intentionally empty
- Single emoji in a small **circular white chip** — no text
- No scrapbook chrome (no avatars, sticky notes, paperclips, stamps, flags, ribbons)
- Home: **two-column grid** of collection pockets

### Pull-to-refresh (screenshot resync)
- Home `ScrollView` supports **native pull-to-refresh**
- Manual fallback for users who want an immediate library check
- **Automatic / background incremental sync remains the primary product behavior** (later sprints)
- Production sync must be **incremental**: compare Photos assets to known IDs/hashes; process only added / removed / changed screenshots — never re-analyze the whole library on every pull
- Sprint 2: mock sync delay + toast (`Screenshots synced` / `N new screenshots organized` / `Everything is up to date` / **`Couldn't refresh screenshots`** on failure — never show success copy on failure)

**Not on Home as primary cards:** Type Facet browse (Receipt, Flight as folders).

Should feel like *printed photos in a compact document sleeve* — premium Apple folder density.

**Below threshold:** new AI contexts stay off Home until ≥ threshold members or user pins (see Settings/default = 3).

---

## Navigation

**Floating pill tab bar** (locked): Home · Search · Cleanup · Settings  

- Shown on **tab roots only** — hidden on Context / Screenshot Detail (and any pushed screen)  
- Lightweight — avoid heavy glass  
- Usability over decoration


---

## Collection Detail
- **3-column** square thumbnail gallery (no list view; no per-shot titles/OCR/tags)  
- Header: collection name + subtle screenshot count  
- **•••** menu (lightweight): Rename / Change Emoji · Delete Collection  
- **Select** → multi-select (Select All / Deselect All; selected count)  
- With selection: **Move** · **Delete** (delete confirms; Sprint 2 mock only)  
- Outside selection: tap → fullscreen Screenshot Viewer  

### Collection management (MVP — manual, lightweight; AI-first still primary)
- **Create** collection: name + emoji only (native emoji keyboard; **no** preset emoji grid)  
  - Home entry: quiet **New Collection** tile as the **last** item in the Collections grid (not a header “+”)  
- **Rename** / change emoji — updates everywhere immediately  
- Success feedback via reusable **STToast** dark floating snackbar (auto-dismiss ~2.5s; ~5s with **Undo**); confirms stay for destructive actions only  
- Reversible mock ops (delete/move/collection-only) expose **Undo** on the snackbar; store owns restore — not the toast UI. Production PhotoKit deletes must not fake Undo unless assets can truly be restored.  
- **Delete Collection** confirmation with dual path:  
  1. **Delete Collection Only** — removes the collection; screenshots stay in Photos; members with no other membership → **Needs Review**  
  2. **Delete Collection & Screenshots** — also removes those screenshots from Photos (strong confirm; Sprint 2 = mock)  
- Never one-tap destroy Photos assets  

### Move screenshots (MVP)
- Move selected → collection picker (other contexts)  
- **+ New Collection** in picker → name + emoji → Create & Move  
- Empty source collection may remain empty (do not auto-delete)  

Archived collections are hidden from Home but remain searchable / restorable (MVP: archive = hide from Home). Merge remains a later/stretch action unless already shipped.

---

## Screenshot Viewer
- Fullscreen, Photos-style image viewer (not a document detail screen)  
- Swipe between screenshots in the same Collection; preserve position  
- Optional subtle position indicator (“3 of 12”)  
- Share via native iOS share sheet  
- **No** per-screenshot titles, OCR/text blocks, entities, facets, or AI metadata in UI  

Internal classification signals (OCR, facets, entities, multimodal cues) may still exist for organization/search — they are **not** user-facing on this screen. Classification must not require readable text; textless screenshots remain valid.

---

## Search
Core experience. Local-only once indexed. **Describe what you remember** — ScreenTidy finds the screenshot.

### Behavior (locked)
- **Real-time** as the user types (debounce ~250ms). No Submit / Return required.  
- Cancel stale searches when the query changes.  
- Placeholder: **Search your screenshots**  
- Mental model: “I describe what I remember” — not “I know ScreenTidy’s metadata.”

### Result UI
- **3-column** square thumbnail gallery (same language as Collection Detail)  
- No titles, OCR snippets, AI tags, or descriptions on tiles  
- Strong Collection name matches may appear in a **Collections** section **above** Screenshots  
- Tap → existing fullscreen Screenshot Viewer; swipe through **current search result set**  
- Empty query: calm ready state — “Find any screenshot” + “Search by text, objects, places, or Collections.” + **Try searching for** suggestion chips (Sprint 2 mock prompts; later library/recents-aware). Chip tap fills the field and runs search immediately.  
- Suggestions hide while typing; return when the query is cleared. 
- No results: “No screenshots found” · “Try another word or description.” (not an error)

### Signals (internal — not shown in UI)
Architecture combines (Sprint 2 = mock; later = real indexes):
1. OCR / visible text  
2. Visual / object understanding (textless screenshots remain searchable)  
3. Collection titles  
4. Semantic / organization metadata  
5. Date / recency (hooked for later NL time queries)

### Architecture
`SearchView` → `SearchViewModel` → `SearchProviding.search` → `SearchResponse` (`collections` + ranked `SearchHit` with `relevanceScore` + `matchedSignals`).  
Do not embed ranking logic in the view. Production Search engineering sprint owns indexes/embeddings/ranking weights.

Filters (Collection / Type Facet / Favorites) remain a later polish — not required for Sprint 2 mock UX validation.

## Cleanup
MVP categories only:
1. **Duplicates** — grouped visually; metadata like “32 screenshots · 14 groups”  
2. **Old Screenshots** — creation date older than **6 months** (threshold configurable later; UI exposes 6 months only)

**Not in MVP:** Expired / flight-date, receipts, large files, similar, AI cleanup categories.

Review UX:
- **3-column** thumbnail gallery (dense scan; not Context Detail layout)  
- Multi-select with Select / Select All ↔ Deselect All  
- Delete only after selection + confirmation (“Delete N Screenshots?” / Photos library copy)  
- Never auto-delete  
- Tap (non-selecting) → existing fullscreen Screenshot Viewer  

Sprint 2 uses **mock deletion** (`mockRemoveScreenshots`) — architecture ready for PhotoKit later; Photos is not modified yet.

---

## Settings
- Photos access status (Sprint 2 mock: Full Access / Limited Access / Access Off)  
- About / version / environment  
- Developer: Replay Onboarding (+ DEBUG Empty Library Onboarding)  
- Organization is **always on** — no AI organization toggle, no AI consent screen  
- Rebuild Library / index rebuild: deferred until real import architecture  
- No account section  

---

## States
Loading, Empty, Error, Permission denied, Offline, Partial organization — never blank; progressive contexts OK.

---

## Motion
Hero into Collection; calm progressive organization; respect Reduce Motion.

---

## Copy Tone
- “Organized into Japan Trip” — not “Classified as Hotels.”  
- Destructive Photos language stays serious and plain.
