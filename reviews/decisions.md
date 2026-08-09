# ScreenTidy — Decision Log

Permanent historical memory of major product, UX, and engineering decisions.  
See `reviews/README.md` for workflow.

---

## D-001 — Local-first architecture
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** ScreenTidy is local-first. Screenshot bytes stay in Apple Photos; organization metadata lives on device (SQLite+FTS planned). No auth, no cloud library sync in MVP.

**Alternatives:** Supabase/BaaS as system of record; cloud-synced library.

**Why:** Matches Privacy First; removes sync/auth complexity for MVP; enables offline browse/search.

---

## D-002 — Hybrid ephemeral AI (not pure on-device or cloud library)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** On-device OCR + optional ephemeral cloud multimodal organization. No permanent server image storage. Stateless AI gateway only.

**Alternatives:** Pure on-device classify; full cloud backend with stored images.

**Why:** Classification quality needs cloud multimodality for “magical” contexts; durable data stays local to honor privacy.

---

## D-003 — Context Collections over fixed taxonomy (Option C)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Primary organization is dynamic **Context Collections** (Japan Trip, Visa Application). **Type Facets** + **Entities** are secondary metadata. Low confidence → **Unassigned**.

**Alternatives:** Fixed taxonomy Home (Option A); unconstrained free naming without discipline (Option B).

**Why:** People remember life contexts, not file types. Fixed taxonomy feels like an AI file manager. Pure free naming becomes chaotic without reuse/merge rules.

---

## D-004 — Assistant discipline for contexts
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Reuse-before-create; high confidence to mint; Home promotion threshold (default 3) unless pinned; minimize reorganization churn.

**Why:** A thoughtful assistant attaches to existing piles; unconstrained creation destroys trust.

---

## D-005 — Dual delete paths
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** “Remove from ScreenTidy” ≠ “Delete from Apple Photos.” Photos delete always requires explicit confirmation. Undo where practical for remove-from-app only.

**Why:** Trust. Accidental Photos deletes are unforgivable.

---

## D-006 — SQLite + FTS5 (GRDB) over SwiftData for MVP store
**Date:** 2026-08-08 · **Status:** Locked (package in Sprint 3)

**Decision:** Local metadata + search via SQLite/FTS5, GRDB preferred. Not linked until Sprint 3.

**Why:** Search is core; 10k-scale FTS and explicit control beat SwiftData convenience.

---

## D-007 — iOS 17+ minimum
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Deployment target iOS 17.0.

**Why:** Observation, modern SwiftUI navigation, Vision quality; acceptable MVP floor.

---

## D-008 — No analytics / monetization in MVP
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** No Firebase, RevenueCat, or paywalls until PMF validation.

**Why:** Validate memory-organization magic first.

---

## D-009 — Home direction: Quiet Pocket (Direction A)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Home uses Quiet Pocket — soft neutral pocket cards with peeking 3–4 screenshot stacks. Collections are the hero.

**Alternatives:** B Glass Shelf (carousel); C Editorial Air (type-led).

**Why:** Best preview-before-title, calm, scalable, moodboard-aligned without copying layouts. Screenshots are the visual identity.

---

## D-010 — Native system tab bar (Liquid Glass)
**Date:** 2026-08-08 · **Status:** Locked (supersedes custom floating pill)

**Decision:** Use native SwiftUI `TabView` for top-level navigation (Home · Search · Cleanup · Settings). On current iOS SDKs the system tab bar provides floating Liquid Glass, safe-area positioning, selection treatment, and accessibility. ScreenTidy tints selection with `#008BFF` via `.tint(STColor.primary)`.

**Alternatives:** Custom `FloatingTabBar` (Liquid Glass imitation + visual-only horizontal drag).

**Why:** Apple HIG + *Adopting Liquid Glass* prefer standard navigation components so the system owns glass, scroll-edge behavior, and a11y. Custom dock fought safe area (excess bottom gap), forced Light-only glass overrides, and added non-HIG drag. Per-tab `NavigationStack` state is preserved. Do **not** use `Tab(role: .search)` — it relocates Search to the trailing end and would change IA order.

**Minimize-on-scroll:** Not enabled. `tabBarMinimizeBehavior` is opt-in and global. ScreenTidy already hides the tab bar on pushed details; primary tabs should stay stably available for switching. Revisit later only if gallery/Search browsing clearly benefits — use the official API, never a custom collapse.

**Migration note:** Custom `FloatingTabBar.swift` removed.

---

## D-011 — Screenshots as visual identity
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Never use generic folder icons as primary collection representation. Collage/peek of real screenshots defines ScreenTidy.

**Why:** Content-first product; folders read as file managers.

---

## D-012 — Moodboards as visual source of truth
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** `docs/moodboards/` informs visual principles. Extract principles; do not copy layouts.

**Why:** Shared craft language without cloning reference apps.

---

## D-013 — Quiet Pocket collage composition
**Date:** 2026-08-08 · **Status:** Locked (craft iteration)

**Decision:** Context Collection collage uses an **asymmetric fan of portrait screenshot peeks** tucked into the top lip of a soft neutral pocket — not a flat 2×2 mosaic and not title-first editorial strips.

**Alternatives:** Flat mosaic fill; glass frosted band; type-led filmstrip.

**Why:** Preview-before-title; moodboard peek/stack language without copying layouts; reads as physical memory piles; unique ScreenTidy signature.

---

## D-014 — Pocket sleeve card (max 3 peeks, meta below)
**Date:** 2026-08-08 · **Status:** Locked (craft iteration)

**Decision:** Context Collection Card is a soft **rounded sleeve/pocket**. At most **3** screenshots peek from the opening (upper portion only), subtly fanned and tucked behind the lip. Title and count sit **below** the pocket. No flags, clips, stickers, stamps, avatars, or travel decorations — identity from screenshots + pocket + type + spacing + soft depth only.

**Alternatives:** 4 peeks; title inside pocket body; decorative scrapbook chrome.

**Why:** Works for every screenshot type; screenshots remain the visual signal; calmer and more Apple-native; principles from pocket reference without copying travel décor.

---

## D-015 — Reference composition + context badge (not travel décor)
**Date:** 2026-08-08 · **Status:** Locked (craft iteration)

**Decision:** Adopt the pocket reference’s **overall composition** for ScreenTidy: large soft rounded pocket, generous empty flap, three peeking screenshots (natural fan), calm layered shadows, **two-column Home grid**. Context hint is a **single emoji** (no text label). Remove avatars, sticky notes, paperclips, stamps, flags, and ribbons entirely. Visual identity = screenshots + pocket + title + emoji — a beautiful folder of memories, not a travel app or file manager.

**Alternatives:** Emoji + text badge; copy reference décor; single-column wider cards.

**Why:** Reference proportions and physical feel are the right language; emoji-only keeps the hint secondary; screenshots remain the hero.

---

## D-016 — Title inside pocket + circular emoji chip
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Emoji stays **top-left** in a circular white chip. Title + metadata sit **bottom-left** inside the pocket (~18–20pt left, ~18–24pt bottom) with intentional empty middle — not a tight top cluster. The whole unit reads as one premium memory-folder object.

**Alternatives:** Title below pocket; tight top cluster (interim); centered title.

**Why:** Matches a physical pocket label placement; upper area stays clean while typography anchors the base.

---

## D-017 — Screenshots physically inside the sleeve (not on the card)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Context Collection pocket uses document-sleeve layering: screenshots render **behind** a separate white pocket front panel that overlaps ~**60%** of each shot. Peeks are not clipped into a shared card silhouette and must not sit on top of / outside the pocket. Exactly 3 fanned peeks (center highest). Component: `ContextCollectionPocketView`.

**Alternatives:** Shared clipShape card with peeks in the top band; peeks as overlays above the pocket.

**Why:** Only true behind/front overlap creates the “photos inserted into a sleeve” illusion from the reference.

---

## D-018 — Compact folder proportions (reference parity rebuild)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Rebuild pocket geometry for reference density: folder ~**25–35% shorter**, overall aspect ~square (not tall), **larger** peeks (~40% visible), emoji top-left + title/meta bottom-left with clean middle. No scrapbook décor.

**Alternatives:** Tall empty pocket; title pinned in a tight top cluster only.

**Why:** Tall empty folders read as generic cards; compact filled folders read as memory sleeves.

---

## D-019 — Quiet Pocket Design System is the visual foundation
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Sprint 1 Design System (`Core/DesignSystem`) is the **locked visual foundation** for ScreenTidy. Future screens must reuse tokens (`STSpacing`, `STRadius`, `STColor`, `STShadow`, `STTypography`, `STMotion`) and components (`ContextCollectionPocketView`, `STEmojiBadge`, `STGreetingHeader`, `STSearchField`, `STPage`, `STPrimaryCard`, native `TabView` shell, etc.). Do not invent parallel styling. Sprint 2 may begin only after this lock.

**Alternatives:** Defer DS extraction; allow per-screen one-off styling.

**Why:** Prevents visual drift; Home pilot proved the language; reuse accelerates Sprint 2+ UI shell.

---

## D-020 — Photos permission edge-case UX (never stuck)
**Date:** 2026-08-08 · **Status:** Superseded by D-021

**Decision:** (Original) Allow Continue without Photos into a usable empty Home.

**Superseded because:** Photos access is a product prerequisite for ScreenTidy’s core function.

---

## D-021 — Photos access is mandatory (Exit, don’t Continue without)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Photos access (Full or Limited) is **required**. Don’t Allow shows recovery: **Enable Photos Access** (primary) and **Exit ScreenTidy** (secondary). No “Continue without Photos”; no Home without access. Exit does not complete onboarding. Later: Enable deep-links to Settings and resumes onboarding when granted. Zero screenshots after grant remains a friendly empty Home. See `docs/02_UX_SPEC.md`.

**Alternatives:** Continue without Photos (D-020); force Settings sheet only with no Exit.

**Why:** Without screenshots, ScreenTidy cannot organize Context Collections — an empty shell misrepresents the product.

---

## D-022 — Organizing onboarding uses the real Context Collection library UI
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** The final onboarding step (“Building your Context Collections”) progressively reveals the **actual** Context Collections that will appear on Home — dynamically titled/emoji’d/previewed/counted from organization (mock store now; Photos + AI later). Onboarding and Home share one model and **`ContextCollectionPocketView`** only — no onboarding-specific pocket component. Reveal → finish → Home shows the same library.

**Alternatives:** Static decorative sample cards; separate onboarding pocket UI.

**Why:** Single source of truth; user sees ScreenTidy build their real memory library; avoids throwaway UI.

---

## D-023 — AI consent copy is benefit-first (not infrastructure)
**Date:** 2026-08-08 · **Status:** Superseded by D-024

**Decision:** (Earlier) Opt-in framing for AI organization.

**Superseded because:** AI organization is a core default, presented as a preference.

---

## D-024 — AI organization on by default (preference, not permission)
**Date:** 2026-08-08 · **Status:** Superseded by D-032

**Decision:** Onboarding presents **AI Organization** as a Personalization preference with the toggle **ON by default**. Copy is short and benefit-first (“Use AI organization”). Users can turn it off anytime in Settings. Privacy/temporary processing lives behind a subtle **Learn More** — not on the main screen. Avoid infrastructure jargon.

**Superseded because:** Organization is always-on core product with no user-facing toggle (D-032).

---

## D-025 — Visual browsing over per-screenshot metadata UI
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Context Collection Detail is a **3-column square thumbnail gallery**. Screenshot Viewer is a **fullscreen Photos-style pager** (swipe + share + optional “n of m”). Do **not** expose AI/OCR titles, descriptions, extracted text, entities, or tags on these screens. Classification signals stay **internal** (organization/search). Classification must not depend exclusively on OCR — textless screenshots remain valid.

**Alternatives:** Document-style Screenshot Detail with OCR/entities; list↔grid toggle; 2-column iPhone-ratio tiles.

**Why:** ScreenTidy’s job is Screenshots → Context Collections → simple visual browsing. The collection name is the context; explaining every screenshot turns the product into a document manager.

---

## D-026 — Cleanup MVP = Duplicates + Old only
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Cleanup answers “what can I probably remove?” with exactly two categories: **Duplicates** (grouped) and **Old Screenshots** (creation date older than 6 months). Review uses a **3-column** multi-select gallery, Select All / Deselect All, and explicit delete confirmation. Never auto-delete. No Expired / receipts / large files / AI cleanup categories in MVP. Sprint 2 deletion is **mock-only** (`mockRemoveScreenshots`); PhotoKit comes later.

**Alternatives:** Keep Expired/flight-date suggestions; document-style cleanup rows; auto-select all duplicates in a group.

**Why:** Focus Cleanup on clutter reduction. Expired needs richer date intelligence later; auto-selecting every duplicate risks deleting the keeper.

---

## D-027 — Collection & screenshot management (MVP manual controls)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** MVP includes lightweight manual collection/screenshot controls while remaining **AI-first**:
- Create collection (name + emoji only; **native emoji keyboard**, no curated emoji grid)  
- Rename / change emoji  
- Delete Collection with dual path: **Collection Only** (Photos safe; orphans → Unassigned) vs **Collection & Screenshots** (strong Photos confirm; Sprint 2 mock)  
- Context Detail: **3-column** gallery + Select / Move / Delete selected  
- Move picker includes **+ New Collection** (create & move)  
- Fullscreen viewer stays metadata-free  
- Success feedback via reusable **STToast** (confirmations remain for destructive actions only)

**Alternatives:** Defer all manual org to Sprint 5; auto-delete empty collections; single delete that always removes Photos; in-app emoji preset grid.

**Why:** Users need escape hatches to correct AI without turning ScreenTidy into a folder app. Dual delete prevents accidental Photos loss. System emoji keyboard covers all emoji without maintenance.

---

## D-028 — Needs Review (user-facing Unassigned)
**Date:** 2026-08-08 · **Status:** Locked (chrome clarified Sprint 2 close-out)

**Decision:** Internal `kind = unassigned` remains. **User-facing** name is **Needs Review**. Home shows a **compact** soft card only when count > 0, between greeting and Collections:

- Leading 2–3 overlapping screenshot peeks  
- Title: “[N] screenshots need your help”  
- Description: “Review where these screenshots belong”  
- **Entire card tappable**  
- **No** sparkle icon · **No** oversized Review CTA  

Detail reuses Collection gallery selection/move/viewer with title “Needs Review”. Do not invent collections to empty this inbox; low confidence asks the user.

**Alternatives:** Keep “Unassigned”; force auto-place; always show a zero-count row; sparkle + Review button (earlier exploration — superseded).

**Why:** “Unassigned” is database language. Compact peeks + human copy communicates the action without decorative chrome.

---

## D-029 — Primary brand color #008BFF
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** ScreenTidy’s canonical primary is **`#008BFF`**, exposed as `STColor.primary` (+ `primaryPressed`, `primarySubtle`). Asset `AccentColor` matches. Use for primary CTAs, links, selection chrome, toggle tint, and native `TabView` selection via `.tint(STColor.primary)`. Do not mix system blue / green / ad-hoc hex for primary actions. Destructive remains red.

**Alternatives:** Keep system `Color.accentColor`; purple brand; solid blue selected tab pill.

**Why:** One consistent action color across onboarding, Home chrome, and navigation. Subtle selected pill stays Quiet Pocket–calm.

---

## D-030 — Home pull-to-refresh (incremental resync)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Home supports **native pull-to-refresh** as a **manual** screenshot library resync. Production must sync **incrementally** (delta vs known assets) and only process changes. Automatic background sync remains primary. Sprint 2 ships `ScreenshotSyncing` + `MockScreenshotSyncService` with short delay and STToast feedback. Failure must show **`Couldn't refresh screenshots`** — never success copy (`Screenshots synced`) on failure.

**Alternatives:** No manual refresh; full-library reprocess on pull; custom non-native spinner.

**Why:** Users sometimes want an immediate check without leaving the app; incremental design protects performance at 10k-scale libraries.

---

## D-031 — Snackbar Undo for reversible mock mutations
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** `STToast` supports an optional trailing action. Standard action is **Undo** in primary `#008BFF`. Informational hold ~2.5s; with Undo ~5s. Undo state is owned by `MockMemoryStore` (`MockUndoToken` + snapshot), not the toast UI. Wire Undo for delete screenshots, move, and delete collection (Sprint 2 mock). Do **not** advertise Undo for production PhotoKit deletions unless assets can be reliably restored.

**Alternatives:** Separate undo banner component; permanent snackbar until dismissed; green Undo accent.

**Why:** One shared snackbar keeps Quiet Pocket chrome calm; store-owned undo keeps future Photos integration honest.

---

## D-032 — Organization always on (no AI toggle)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Organizing screenshots into Collections is **core product** and always enabled. Remove the onboarding **AI Organization / Personalization** step and the Settings **Use AI organization** toggle. Clear obsolete `screentidy.ai.organizationEnabled` persistence. Prefer benefit copy (“Organizes screenshots into Collections”) over implementation jargon. Keep architecture able to separate on-device vs future network processing for privacy/disclosure — that is not a user-facing enable/disable preference. Sprint 2 remains mock-only.

**Alternatives:** Keep default-on preference (D-024); separate “cloud processing” toggle only (deferred until a real network path exists).

**Why:** Users should not configure the classification mechanism to use ScreenTidy; AI is the mechanism, not a setting.

---

## D-033 — User-facing term is Collections (not Context Collections)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** All **user-facing** UI copy uses **Collection / Collections**. Do not teach “Context Collections.” Internal types (`ContextCollection`, docs for engineers) may keep the longer name. Preferred verbs explain benefit (“organizes into Collections”), not mechanism (“AI classification,” “metadata,” “index”). Onboarding copy simplified for non-technical users (Welcome / Photos / Organizing locked strings in `02_UX_SPEC.md`).

**Alternatives:** Keep “Context Collections” as branded vocabulary; hyphenate “context-collections.”

**Why:** Users should understand ScreenTidy immediately without learning product jargon.

---

## D-034 — Real-time multi-signal Search (Sprint 2 mock)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:** Search updates as the user types (debounce ~250ms, cancel stale work). Architecture is `SearchProviding` → `SearchResponse` with ranked `SearchHit` + internal `SearchSignal`s (OCR, visual, collection, semantic, date). UI is visual-only: 3-column thumbnails, optional Collections section above, calm empty/ready states, viewer gallery = result set. Sprint 2 mocks multi-signal matching on enriched fixture data — no production OCR/embeddings/network. Placeholder: “Search your screenshots.” Intelligence stays behind the interface.

**Alternatives:** Submit-to-search only; OCR-only search; document-style result rows with snippets.

**Why:** Users find screenshots by what they remember (text, objects, places, Collections), not by knowing metadata fields.

---

## D-035 — Sprint 2 close-out polish (sync failure, Settings Photos, empty library, protocol VMs)
**Date:** 2026-08-08 · **Status:** Locked

**Decision:**
1. Pull-to-refresh maps failure → `ScreenshotSyncResult.failed` / toast **Couldn't refresh screenshots** (never success copy).  
2. Settings Photos reflects mock access: Full Access / Limited Access / Access Off; **Rebuild Library** hidden until real indexing.  
3. DEBUG Developer action **Empty Library Onboarding** reaches the zero-screenshot onboarding step.  
4. Empty-library progress VoiceOver label is **No screenshots found** (not Organizing).  
5. Feature ViewModels depend on `MemoryReading` / `MemoryRepository` protocols — not concrete `MockMemoryStore`.  
6. Needs Review chrome locked per updated D-028 (compact; no sparkles/Review CTA).

**Why:** Sprint 2 acceptance requires a truthful mock UX contract and a clean boundary for Sprint 3 persistence/Photos adapters.

