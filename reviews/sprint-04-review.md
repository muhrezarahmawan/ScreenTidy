# Sprint Summary

**Sprint:** 04 — Real Photos Integration (READ / SYNC)  
**Date:** 2026-08-08  
**Status:** **CLOSED / ACCEPTED**

---

## Acceptance

**Accepted by:** Product owner (physical-device verification)  
**Date:** 2026-08-08  

Device verification passed on a real iPhone. Engineering DoD + owner DoD #22 complete.

---

## Navigation (D-010)

Migrated custom `FloatingTabBar` → native SwiftUI `TabView` (system Liquid Glass, `#008BFF` tint, per-tab `NavigationStack`).

## Physical-device visual blocker (resolved)

**Symptom:** White/faint text on light surfaces; dark charcoal chrome on real iPhone (system Dark Mode).  
**Fix:** Semantic text tokens; MVP Light Mode lock. Verified as part of Sprint 4 acceptance.

## Milestone

**These are now my real screenshots.**  
Not: ScreenTidy can modify/delete my Photos library.

---

## Physical-device verification (accepted)

Verified on real iPhone:

| Check | Result |
|-------|--------|
| Full Photos access — real screenshots appear | Pass |
| Limited Photos — accessible subset reflected | Pass |
| Access revoked / None handled gracefully | Pass |
| Existing Collections survive permission revocation | Pass |
| Pull-to-refresh discovers newly added screenshots | Pass |
| New screenshots appear in Needs Review | Pass (**expected** Sprint 4 behavior — not a bug) |
| Real thumbnails load smoothly | Pass |
| 3-column galleries perform well | Pass |
| Fullscreen viewer works | Pass |
| Share works | Pass |
| Kill/relaunch preserves Collections + screenshot state | Pass |
| Large-library scrolling remains smooth | Pass |
| Restoring Photos access reconciles without duplicating/destroying organization | Pass |

**Notes (non-blockers):**
- “Couldn't refresh screenshots” snackbar when Photos access is revoked is acceptable for now.
- iCloud-only screenshot load path was **not** explicitly tested; deferred; not a Sprint 4 blocker.

---

## Delivered

| Item | Status |
|------|--------|
| Auth `.readWrite` least privilege (documented) | Done |
| `NSPhotoLibraryUsageDescription` (discover/display; no Photos delete) | Done |
| Discovery (`photoScreenshot` subtype) | Done |
| GRDB `v2_photos` (`source`, `access_state`, unique local ID) | Done |
| Fixture clear keyed by `source` + `app_meta` (initial + incremental) | Done |
| Import → Needs Review only | Done |
| Incremental reconcile + observer + launch/foreground/pull | Done |
| Observer → `noteMemoryMutation` UI refresh | Done |
| `ThumbnailProviding` / `PHCachingImageManager` | Done |
| Viewer + share (network allowed) | Done |
| Onboarding real import / empty / DEBUG empty force | Done |
| Settings status + Limited Manage | Done |
| Home Needs Review count + 3 peeks | Done |
| Paged Collection galleries | Done |
| Metadata-only remove (“Remove from ScreenTidy”) | Done |
| No `PHPhotoLibrary.performChanges` delete | Done |
| Unit tests (fixture, upsert, Limited inaccessible, peeks, remove metadata) | Done |
| Physical-device verification | **Accepted** |

---

## Architecture notes

- Sync: identifier-set reconcile + `PHPhotoLibraryChangeObserver` — no fake PhotoKit change tokens  
- Limited missing asset → `access_state=inaccessible` (memberships kept)  
- Full missing asset → delete local photos-sourced metadata only  
- **All new imports land in Needs Review** — intentional until understanding / classification sprints  

---

## Explicit non-goals held

PhotoKit deletion · OCR · FTS population · embeddings · AI organization · production Search · real duplicate detection · automatic filing out of Needs Review  

---

## Next

Sprint 4 closed. **Do not start Sprint 5 implementation until the Sprint 5 plan is approved.**  
Sprint 5 scope: on-device screenshot understanding foundation (Vision OCR) — see forthcoming plan / `docs/21_SPRINT_5_OCR.md` when approved.
