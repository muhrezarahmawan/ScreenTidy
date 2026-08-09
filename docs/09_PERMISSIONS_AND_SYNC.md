# ScreenTidy — Permissions & Screenshot Sync

**UX authority for permission edge cases:** `docs/02_UX_SPEC.md` (Onboarding → Photos permission edge cases).  
This doc covers engineering behavior; keep UX copy and recovery patterns aligned with the UX spec.

---

## Photos Access

### Timing
Onboarding after Welcome · Denied recovery · Settings enable / Limited manage · revoke gate after onboarding  

### Prerequisite
**Photos access (Full or Limited) is required** to use ScreenTidy. There is no “continue without Photos” path into Home.

### Levels
| Level | Behavior |
|-------|----------|
| Full | Index screenshots library-wide (screenshot heuristics) |
| Limited | Index selection only + Settings line (“Managing N selected screenshots”) + offer expand selection |
| Denied during onboarding | Recovery screen: Enable Photos Access / Exit ScreenTidy — stay on stage 2 |
| Revoked after grant | Pause organization; **preserve** metadata/contexts; recovery UI with Enable Photos Access |

Identify screenshots via Photos APIs / subtypes — do not import arbitrary photos as memories by default.

### UX rules (summary)
- Don’t Allow → calm in-app recovery (required access copy)  
- Secondary action: **Exit ScreenTidy** (not Continue without)  
- Enable Photos Access → Settings deep-link later; mock grant in Sprint 2  
- Onboarding incomplete until access granted (exit does not mark complete)  
- Zero screenshots **after** grant → friendly Home empty (not a permission failure)  

### Enable Photos Access (future)
Open the app’s page in iOS Settings (`UIApplication.openSettingsURLString`). On return: if authorized, resume onboarding/import; if still denied, remain on recovery.

---

## Incremental Sync

### Initial
Enumerate → upsert by `photosLocalIdentifier` → queue OCR → organization (newest first)

### Ongoing
`PHPhotoLibrary` observer: insert enqueue · delete reconcile · change invalidate thumbs / re-analyze if needed  

### Interrupted import
Resume from checkpoint on next launch — never restart from zero when progress exists. *(Sprint 2: mock only.)*

### Performance
Batch DB writes · bound Vision concurrency · opportunistic background tasks only  

---

## Limited Library UX
Never pretend the full memory library is complete. Offer manage/select more / full access without dark patterns. Settings shows selection count when Limited.

---

## Offline
Local browse, OCR, search, manual Context Collections work **after** Photos access exists.  
AI organization queues until network + consent.

---

## Delete from Photos
In-app explanation → explicit confirm → Photos API → reconcile local DB only after success. Handle system cancel.

---

## Rebuild Index
Re-scan Photos · preserve user contexts/memberships/favorites when identifiers survive · re-queue missing OCR/organization  

---

## iCloud Photos
Assets may be remote-only — show downloading state; don’t permanently fail organization on transient fetch errors.

---

## What this is not
Not cross-device ScreenTidy sync.  
Not a productized iCloud backup of memories (device backup of local DB may still occur — see Open Questions).
