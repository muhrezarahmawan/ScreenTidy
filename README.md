# ScreenTidy

AI-powered **personal memory organizer** for iPhone.

Screenshots stay in Apple Photos. ScreenTidy quietly organizes them into Collections — the way a thoughtful assistant would.

## Source of truth

All product, architecture, UX, and engineering decisions live in [`docs/`](docs/README.md).

Implementation follows documentation unless docs are explicitly revised first.

## Requirements

- Xcode 16+ (recommended)
- iOS **17.0** deployment target
- macOS with full Xcode (not Command Line Tools only) to build

## Open in Xcode

```bash
open ScreenTidy.xcodeproj
```

Select an iPhone simulator and Run.

## Architecture (Sprint 0)

- **Single app target** with modular folders (not micro-packages yet)
- **MVVM** using Observation (`@Observable`) on iOS 17+
- **Tabs + NavigationStack** per tab
- **Composition-root DI** via `AppDependencies` + SwiftUI `Environment`
- **Protocol ports** + **mock** implementations (no Photos / DB / AI / network yet)
- **Design tokens + theme** foundation (full Design System in Sprint 1)
- **SQLite + FTS (GRDB)** planned for Sprint 3 — dependency not linked yet

See `docs/13_IMPLEMENTATION_ROADMAP.md` and `docs/14_WORKING_AGREEMENT.md`.

## Folder map

```
ScreenTidy/
  App/                 # Entry, composition root, root UI
  Core/                # Design system, navigation, DI, logging, errors, config
  Domain/              # Models + repository/service protocols
  Data/                # Mock (later: SQLite, Photos adapters)
  Features/            # Home, Search, Cleanup, Settings (UI shells)
```

## Current sprint

**Sprint 0 — Project Foundation** (no business logic).
