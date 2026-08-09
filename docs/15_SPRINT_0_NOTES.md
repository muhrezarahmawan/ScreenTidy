# Sprint 0 — Foundation Notes

Completed as the official engineering baseline for ScreenTidy.

## Persistence decision (recorded)

| Choice | Decision |
|--------|----------|
| Local DB (Sprint 3) | **GRDB** + SQLite + FTS5 |
| Why | Matches locked architecture; excellent FTS; explicit SQL control for 10k+ memories |
| Sprint 0 | Package **not** linked yet (no database work this sprint) |

## Xcode 26.6 verification (pre–Sprint 1)

| Check | Result |
|-------|--------|
| Deployment target | **iOS 17.0** |
| Swift language mode (project) | **5.0** (compatible with Xcode 26) |
| Bundle ID | `com.screentidy.app` |
| Device family | iPhone only (`TARGETED_DEVICE_FAMILY = 1`) |
| Shared scheme | `ScreenTidy.xcodeproj/xcshareddata/xcschemes/ScreenTidy.xcscheme` |
| Swift typecheck vs iPhoneSimulator26.5 SDK | **Passed** (`swiftc -typecheck`) |
| Full `xcodebuild` destination | May fail until **iOS 26.5 platform/runtime** is installed via Xcode → Settings → Platforms / Components |

### Fixes applied during verification
- Shared Xcode scheme committed (reliable Run destination)
- `@Observable` ViewModels wrapped with `@Bindable` child views so Home/Search/Cleanup actually refresh after mock load
- Unassigned row is a `NavigationLink` into context detail
- `.derivedData/` ignored for local CLI builds

## How to validate in Xcode

See the checklist in the agent reply / below.

### Local validate checklist
- [ ] App compiles
- [ ] App launches in Simulator
- [ ] Home loads greeting + “I organized 12…”
- [ ] Mock collections appear (Japan Trip, Apartment Setup, Qatar Airways, Visa Application)
- [ ] Unassigned row appears and opens detail
- [ ] Search / Cleanup / Settings tabs open
- [ ] Tapping a collection opens detail; tapping a screenshot opens screenshot detail
- [ ] No crash during basic navigation

## Out of scope (intentionally)

Photos · OCR · AI · Search backend · SQLite · Networking · business mutations

## Regenerate Xcode project file list

```bash
python3 Scripts/generate_xcodeproj.py
```

Re-add the shared scheme afterward if regenerating wipes `xcshareddata` (current script does not delete schemes).
