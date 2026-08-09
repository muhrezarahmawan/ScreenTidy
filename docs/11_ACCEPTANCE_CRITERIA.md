# ScreenTidy — MVP Acceptance Criteria

Testable outcomes for MVP “done.” Mental model: **personal memory organizer (Option C)**.

---

## Onboarding
- [ ] Completes Welcome → Photos → Import → Organizing → Home  
- [ ] Progress dots: 4 stages; Photos Permission + Denied Recovery both stage 2  
- [ ] Don’t Allow → recovery: Enable Photos Access / Exit ScreenTidy — no Continue without Photos  
- [ ] Photos access mandatory — no Home without Full or Limited access  
- [ ] Exit does not mark onboarding complete; next launch resumes onboarding  
- [ ] Enable Photos Access (later): Settings deep-link; resume when granted  
- [ ] Limited Photos → import selection only; Settings shows managed count  
- [ ] Revoke after grant → pause org, preserve Collections, recovery UI  
- [ ] Zero / non-screenshot library (with access) → friendly empty, not an error  
- [ ] Copy positions product as memory organizer; user-facing term is **Collections** (not Context Collections)  
- [ ] Privacy: screenshots stay in Photos; organization always on (no AI toggle)  
- [ ] No AI Organization / Personalization onboarding step; no Settings AI on/off preference  
- [ ] Onboarding copy is plain-language (locked Welcome / Photos / Organizing strings)  

## Import & Sync
- [ ] Screenshots indexed from Photos  
- [ ] New screenshots discovered while using / on next active  
- [ ] Deleted Photos assets reconciled out of ScreenTidy  
- [ ] Limited Library incompleteness messaging  

## OCR
- [ ] OCR stored locally; works offline  
- [ ] Failed OCR still browsable  

## Organization (Option C)
- [ ] Screenshots receive Collection membership(s) and/or Needs Review as part of core organization (always on)  
- [ ] Resolver **reuses** existing Collections when titles/aliases match rather than minting duplicates for the same meaning  
- [ ] New Collections require high-confidence create path  
- [ ] Low confidence → **Needs Review**, not speculative Collection titles  
- [ ] Type Facets persisted from allow-list  
- [ ] Entities persisted when returned  
- [ ] User memberships not wiped by later organization runs  
- [ ] Offline: usable app; organization queues or skips safely without a user toggle  
- [ ] No full-library automatic reshuffle on every launch  
- [ ] Future cloud/network processing remains architecturally separable from always-on organization (disclosure/consent if required) — not a Settings “AI off” switch  

## Home / Collections
- [ ] Home shows Collections (collages), not type-facet folders as primary IA  
- [ ] **Needs Review** Home card visible only when non-empty (never “0 screenshots”)  
- [ ] Home supports **pull-to-refresh** (native); Sprint 2 mock sync + toast; production sync is incremental  
- [ ] **New Collection** tile is the last item in the Home grid (no header “+”)  
- [ ] Collections below promotion threshold hidden from Home unless pinned  
- [ ] User can **create** Collection (name + emoji)  
- [ ] User can **rename** / change emoji  
- [ ] User can **delete collection only** (Photos untouched; orphans → Needs Review); Undo restores mock collection in Sprint 2  
- [ ] User can **delete collection & screenshots** with strong confirm (Sprint 2 mock; mock Undo only — not PhotoKit restore)  
- [ ] Context Detail: **3-column** gallery; Select / Select All / Move / Delete selected  
- [ ] Move / delete selected show Undo snackbar while mock restore is available  
- [ ] Move supports **+ New Collection** create-and-move  
- [ ] Merge does not delete Photos assets (merge may be stretch)  
- [ ] UI copy says **Collections**, never “Context Collections”  

## Search
- [ ] Real-time results while typing (debounced; no Submit required)  
- [ ] Mock/Sprint 2 search matches OCR-like text, visual labels, Collection titles, and semantic keywords  
- [ ] Textless / visual-only screenshots remain findable via visual labels  
- [ ] Results are a **3-column** thumbnail grid (no OCR/title/tag chrome on tiles)  
- [ ] Strong Collection matches may appear above Screenshots  
- [ ] Empty query shows calm ready state; no results is not an error  
- [ ] Tap opens Screenshot Viewer with swipe across **current search results**  
- [ ] Search goes through `SearchProviding` → `SearchResponse` (not logic embedded in the view)  
- [ ] Works offline for indexed / mock content  
- [ ] Placeholder: “Search your screenshots”  

## Screenshot Viewer
- [ ] Fullscreen Photos-style preview within a Collection **or** search result set  
- [ ] Swipe previous/next; optional “n of m” indicator  
- [ ] Share via system share sheet  
- [ ] **No** per-screenshot OCR/title/entity/facet UI on this screen  
## Cleanup
- [ ] MVP categories only: **Duplicates** + **Old Screenshots** (no Expired)  
- [ ] Old default **6 months** (creation date; not AI)  
- [ ] Duplicates organized into groups; 3-column grids  
- [ ] Multi-select + Select All / Deselect All; delete only when selection non-empty  
- [ ] Explicit confirmation before delete; never auto-delete  
- [ ] Photos batch delete via PhotoKit — later sprint (Sprint 2 = mock remove only)  

## Performance
- [ ] Path to 10k index remains UI-responsive in internal testing  
- [ ] Import/organization does not freeze UI  

## Privacy / Scope
- [ ] No analytics SDK / auth / library sync backend  
- [ ] No user-facing AI/cloud organization toggle; future network processing stays disclosable separately  
- [ ] No permanent ScreenTidy server library of images  

## Visual / UX bar
- [ ] Floating tabs; calm content-first Home of contexts  
- [ ] No folder-icon collection metaphor  
- [ ] Reduce Motion safe  
