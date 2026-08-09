# Sprint 1 — Design System Complete

**Status:** **Complete** — Quiet Pocket locked; Design System production-ready for Sprint 2  
**Home direction:** A — Quiet Pocket  
**Do not start Sprint 2 until designer acknowledges this close-out**

---

## Locked decisions

| Decision | Choice |
|----------|--------|
| Home direction | Quiet Pocket |
| Signature | `ContextCollectionPocketView` — compact sleeve, 3 peeks, emoji chip, title bottom-left |
| Navigation | Lightweight floating pill |
| Home IA | Greeting 👋 → AI line → search → Unassigned → 2-col pockets |
| Anti-patterns | Dashboard, file manager, folder icons, scrapbook décor |

---

## Design System inventory

### Tokens
`STSpacing` · `STRadius` · `STColor` · `STShadow` · `STTypography` · `STMotion`

### Modifiers
`.stPocketShadow()` · `.stCardShadow()` · `STCardPressStyle` · `.floatingTabBarContentInset()`

### Components
| Component | Role |
|-----------|------|
| `ContextCollectionPocketView` | **Signature** Quiet Pocket |
| `STEmojiBadge` | Context emoji chip |
| `PeekingStackCollage` | 3-peek fan |
| `STGreetingHeader` | Greeting + AI line |
| `STUnassignedRow` | Unassigned teaser |
| `STSectionHeader` | Secondary headers |
| `STSearchField` | Quiet search |
| `STPage` | Page chrome |
| `STPrimaryCard` | Generic soft card |
| `STPrimaryButton` / `STSecondaryButton` | CTAs |
| `STEmptyState` | Empty / error |
| `STScreenshotRow` / `STScreenshotGridItem` | Media rows/tiles |
| `FloatingTabBar` | Pill nav |

---

## How to validate

1. Run app on Simulator  
2. Home: greeting + AI line + search + Unassigned + compact pockets  
3. Pockets: peeks tucked inside; emoji top-left; title bottom-left  
4. Floating pill tabs  
5. Search / Cleanup / Settings use shared tokens & components  

---

## Out of Sprint 1 (intentional)

Real Photos thumbnails · full sheet system · facet/entity chips · onboarding · Sprint 2 full UI shell polish
