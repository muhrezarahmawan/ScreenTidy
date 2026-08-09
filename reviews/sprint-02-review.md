# Sprint Summary

**Sprint:** 02 — Full UI Shell + Mock Data  
**Date:** 2026-08-08  
**Status:** **CLOSED / ACCEPTED**

---

## Goals

- Complete tappable MVP UI with mock data only  
- No Photos / SQLite / OCR / AI / networking  
- Reuse Sprint 1 Design System throughout  
- Screen-by-screen review with designer  

**Outcome:** Mock UI shell accepted as the UX contract for real implementation. Sprint 3 not started.

---

## Acceptance gate

Final audit + close-out polish (P1–P6, P9; optional P7–P8) completed.

| Area | Status |
|------|--------|
| Onboarding (Welcome → Photos → Import → Organizing/Empty → Home) | Pass |
| Empty-library onboarding (DEBUG Developer path) | Pass |
| Home (greeting, subtitle, Needs Review, pockets, refresh, tab bar) | Pass |
| Collections CRUD / select / move / viewer / Undo | Pass |
| Needs Review compact card (locked, no sparkles) | Pass |
| Search real-time multi-signal mock | Pass |
| Cleanup Duplicates + Old only | Pass |
| Settings Photos mock status; no Rebuild Library; no AI toggle | Pass |
| Protocol-based memory boundaries for VMs | Pass |
| Build (iOS Simulator) | Pass |
| Obsolete UI terminology scan | Pass |

---

## Close-out polish (D-035)

1. **P1** — Sync failure → `Couldn't refresh screenshots` (never success toast on failure)  
2. **P2** — Settings Photos: Full Access / Limited Access / Access Off; Rebuild Library removed  
3. **P3** — DEBUG **Empty Library Onboarding** reaches zero-screenshot step  
4. **P4** — Empty stage VoiceOver: **No screenshots found**  
5. **P5** — Needs Review chrome locked; UX/DS docs updated  
6. **P6** — PRD / UX / IA / Design System aligned to Collections + Needs Review  
7. **P9** — `HomeViewModel` / `OnboardingViewModel` depend on `MemoryReading` / `MemoryRepository`  
8. **P7/P8** — Removed `expired` cleanup category + unused `STScreenshotRow`

---

## Locked product contract (Sprint 2)

- User-facing: **Collections**, **Screenshots**, **Needs Review**  
- Primary: `#008BFF`  
- Organization always on (no AI toggle / consent step)  
- Screenshots stay in Photos  
- Mock-first repositories behind protocols  

---

## Explicitly deferred (do not start in this close-out)

- PhotoKit / Limited picker / real Settings deep-link  
- SQLite / GRDB / FTS  
- OCR / embeddings / production Search  
- Network AI gateway  
- Rebuild Library  
- Expired cleanup  

---

## Engineering notes

- `AppDependencies.memoryStore: any MemoryRepository`  
- `MockPhotosProvider` + persisted mock Photos access  
- `ScreenshotSyncResult.failed` + cycling mock failure every 4th pull  
- Decisions: D-028 clarified · D-030 failure toast · **D-035** close-out  

---

## Next

**Sprint 3** — only when explicitly started. Do not auto-begin persistence/Photos work.
