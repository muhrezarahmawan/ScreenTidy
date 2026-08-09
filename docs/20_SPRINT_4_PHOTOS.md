# Sprint 4 — Real Photos Integration (revised)

**Status:** **CLOSED / ACCEPTED** (2026-08-08 — physical-device verification passed)  
**Milestone:** “These are now my real screenshots.”  
**Not:** “ScreenTidy can modify/delete my Photos library.”

### Acceptance note

All imported screenshots landing in **Needs Review** is **expected** Sprint 4 behavior. Automatic understanding / classification was out of scope.

Physical-device results are recorded in `reviews/sprint-04-review.md`.  
Do **not** start Sprint 5 until its implementation plan is approved.

### Navigation correction (2026-08-08)

**Decision gate:** YES — migrate custom `FloatingTabBar` → native SwiftUI `TabView` (see `reviews/decisions.md` D-010).

- System Liquid Glass + safe-area positioning  
- No horizontal dock drag  
- `#008BFF` via `.tint(STColor.primary)`  
- Per-tab `NavigationStack` preserved; tab bar hidden on pushed details  
- `tabBarMinimizeBehavior` **not** enabled (stable primary tabs; details already hide the bar)  
- Do **not** use `Tab(role: .search)` (would reorder Search)  

### Physical-device visual blocker (earlier)

Root cause: light Quiet Pocket surfaces + adaptive `Color.primary` / `Color.secondary` when the device is in Dark Mode → white text on white cards; Liquid Glass also rendered dark chrome.

Fix (Design System):

- Explicit `STColor.textPrimary` / `textSecondary` (never system primary/secondary)
- MVP Light Mode lock via `.preferredColorScheme(.light)` + `UIUserInterfaceStyle = Light`

**Resolved / accepted** with Sprint 4 physical-device verification (2026-08-08).

---

## Non-goals (locked)

- Production PhotoKit deletion (`PHPhotoLibrary.performChanges` delete)
- OCR / FTS population / embeddings / visual understanding
- Production AI organization / networking
- Real duplicate detection / production Search intelligence

Destructive UI uses **metadata-only** behavior with explicit copy (“Remove from ScreenTidy”). Real Photos deletion ships in a later Cleanup/destructive sprint.

---

## Authorization (least privilege) — decision

PhotoKit’s `PHAccessLevel` offers only `.addOnly` and `.readWrite`.

| Level | Can enumerate / read library? | Sprint 4 |
|-------|-------------------------------|----------|
| `.addOnly` | No | Insufficient |
| `.readWrite` | Yes | **Required minimum** |

**Decision:** Request `.readWrite` because it is the *least* PhotoKit level that can discover screenshots, read metadata, request thumbnails/images, and observe Limited-set changes. `.addOnly` cannot power the product.

We **do not** call Photos mutation/deletion APIs in Sprint 4 even though `.readWrite` technically permits them. Broader access is not requested “for a future sprint.”

Mandatory Photos access product flow (Full or Limited) remains unchanged.

Info.plist: `NSPhotoLibraryUsageDescription` explains discover/display; states ScreenTidy does not delete Photos in this build intent.

---

## Fixture → real transition

Explicit column: `screenshot.source` ∈ `fixture` | `photos`.  
**Do not** treat `photos_local_identifier IS NULL` alone as “fixture.”

**One-time cleanup** (`app_meta.fixtureScreenshotsCleared=1`):

1. Delete memberships whose screenshots have `source = fixture`  
2. Delete `screenshot` rows with `source = fixture`  
3. Leave **all** Collections (including user-created) intact  
4. Import real PHAssets as `source = photos` into **Needs Review only**  

Keyed so it never runs twice unless DEBUG reset/reseed clears `app_meta`.

---

## Sync model (no invented PhotoKit tokens)

Reconciliation uses:

1. `PHPhotoLibraryChangeObserver` + retained `PHFetchResult` + `PHFetchResultChangeDetails` when available  
2. Persisted `photos_local_identifier` set in GRDB  
3. Foreground / launch / pull-to-refresh identifier-set reconcile  
4. Our own `app_meta.lastPhotosSyncAt` checkpoint for UX only — **not** a durable PhotoKit change token  

**Limited access:** Asset missing from the accessible fetch → `access_state = inaccessible` (keep row + memberships). When accessible again → `available`. Do not destroy organization on Limited shrink.

**Full library:** Identifier gone → remove local photos-sourced metadata (Photos deleted the asset). Not a PhotoKit delete performed by ScreenTidy.

---

## Needs Review scale

Real screenshot discovered → persist metadata → Needs Review.  
No fake AI filing into Japan Trip / Qatar Airways / etc.

Home Needs Review card:

- SQL `COUNT(*)` for badge  
- at most **3** preview assets for peeks  

Collection galleries page metadata (`limit`/`offset`); thumbnails load lazily via `PhotosThumbnailImage` + cancellation on reuse.

---

## Thumbnails / iCloud

`ThumbnailProviding` → `PhotoKitThumbnailProvider` → `PHCachingImageManager`  
Target sizes for peeks / 3-col / viewer. Grid: `allowsNetworkAccess = false` (placeholder while not local). Viewer/share: network allowed + loading/failure via placeholder. “Not downloaded yet” ≠ missing screenshot.

---

## Search / Cleanup (intentionally incomplete)

- **Search:** real screenshot rows + real thumbs + **temporary mock ranking** over fixture-era fields. **Not** representative of final intelligence. No OCR / FTS population / embeddings in Sprint 4.  
- **Cleanup:** real thumbs OK; duplicate/old detection remains mock; removals are **metadata-only** with clear copy. No PhotoKit deletion.

---

## Implementation order (executed)

1. Sprint 3 CLOSED / ACCEPTED  
2. Authorization architecture  
3. Discovery  
4. GRDB v2 / identity + `source` / `access_state`  
5. First import + fixture transition  
6. Incremental reconciliation  
7. Change observation  
8. Thumbnails  
9. Fullscreen viewer + share  
10. Onboarding import/empty  
11. Settings / Limited manage  
12. Pull-to-refresh + foreground reconcile  
13. Large-library pass (Home peeks + paged gallery)  
14. Tests  
15. Docs + completion report  

---

## Definition of Done (revised)

1. Real PhotoKit authorization drives onboarding and Settings.  
2. ScreenTidy discovers actual screenshot `PHAsset`s.  
3. Real screenshot metadata persists in GRDB.  
4. Screenshot bytes remain owned by Apple Photos.  
5. Real thumbnails appear in Quiet Pockets and 3-column galleries.  
6. Fullscreen viewer displays real screenshots.  
7. Share works with real screenshots.  
8. New screenshots can be discovered incrementally.  
9. Home pull-to-refresh performs real reconciliation.  
10. Photo library changes are handled appropriately.  
11. Limited Photos behaves correctly (`inaccessible` vs deleted).  
12. Revoked access behaves correctly (sync no-ops; Settings Access Off; thumbs degrade gracefully).  
13. iCloud-backed screenshots fail/load gracefully.  
14. Zero-screenshot state works from real PhotoKit data.  
15. Large libraries do not block the main UI (Home count+3; paged galleries).  
16. New unorganized screenshots enter Needs Review.  
17. Sprint 2 UX remains visually unchanged.  
18. Sprint 3 persistence remains intact.  
19. No OCR / FTS / embeddings / AI / networking / production Search was introduced.  
20. No production PhotoKit deletion was introduced.  
21. Automated tests pass.  
22. Physical-device verification succeeds (product owner). → **Accepted 2026-08-08**
