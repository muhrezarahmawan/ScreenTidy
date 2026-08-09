# ScreenTidy — Design System

**Status:** **Locked** — Sprint 1 complete · visual foundation for all future screens  
**Home direction:** Quiet Pocket (Direction A)  
**Signature:** `ContextCollectionPocketView`  
**Navigation:** Floating pill tab bar  

Companion: `04_VISUAL_DIRECTION.md`, `docs/moodboards/`, `16_HOME_DIRECTION_EXPLORATION.md`, `17_SPRINT_1_DESIGN_SYSTEM.md`

---

## Visual principles (locked)

Calm · Spacious · Apple-native · Editorial · Content-first · Premium · Minimal · Soft depth

**Regression signals:** dashboard widgets, analytics strips, file-manager chrome, generic folder icons, rainbow category colors, heavy glassmorphism, scrapbook décor (avatars, stickies, paperclips, stamps).

---

## Home information architecture (locked)

```
Good evening 👋
[rotating approved subtitle from STHomeCopy]
Needs Review (only when count > 0) — compact peeks + copy; entire card tappable
Collection pockets (hero, 2-column) + New Collection tile (last cell)
```

No Home search field. Search lives in the floating tab bar.

---

## Folder structure (code)

```
Core/DesignSystem/
  Tokens/DesignTokens.swift      STSpacing · STRadius · STColor · STShadow · STTypography · STMotion
  Theme/AppTheme.swift           Environment theme
  Modifiers/STViewModifiers.swift  stPocketShadow · stCardShadow · STCardPressStyle
  Components/
    ContextCollectionPocketView  Signature Quiet Pocket
    PeekingStackCollage          3-peek fan + ScreenshotPreview
    (Tab bar)                    Native SwiftUI `TabView` in `RootView` — system Liquid Glass
    STEmojiBadge
    STChrome                     STGreetingHeader · STSectionHeader
    STNeedsReviewCard            Home Needs Review (compact peeks + copy; kind=unassigned)
    BaseComponents               STPage · STSearchField · STPrimaryCard · buttons · empty
    STScreenshotViews            STScreenshotGridItem
```

Feature screens **compose** these components — they must not re-declare pocket shadows, radii, or greeting typography.

---

## Tokens

### Spacing (`STSpacing`)
| Token | Value | Use |
|-------|-------|-----|
| page | 24 | Horizontal page padding |
| homeSection | 28 | Home block rhythm |
| settingsSectionGap | 22 | Settings: end of section → next label |
| settingsLabelToCard | 8 | Settings: label → card |
| settingsCardToFooter | 8 | Settings: card → helper copy |
| settingsRowVertical | 12 | Settings row padding |
| settingsToggleVertical | 14 | Settings toggle row padding (if used) |
| tabBarHeight | 49 | Approx system tab bar height (toast overlay only) |
| toastTabBarGap | 12 | Gap between toast and tab bar |
| tabBarClearance | 16 | Optional breathing above system tab inset (`STPage` only) |

### Radius (`STRadius`)
pocket **26** · settingsGroup **16** · searchField **14** · screenshotTile **14** · galleryTile **18** · button **14** · sheet **20**

`STAspect.iphoneScreenshot` — fullscreen Screenshot Viewer only (~9:19.5).  
`STAspect.galleryTile` — Context Detail 3-column cells (1:1).

### Color (`STColor`)
background · backgroundSecondary · pocket · label · secondaryLabel · **primary (#008BFF)** · primaryPressed · primarySubtle · accent *(alias → primary)* · destructive · hairline · tabBarFill · homeAtmosphere* · onboardingAtmosphere*

**Primary brand lock: `#008BFF`**

| Token | Use |
|-------|-----|
| `STColor.primary` | Primary CTA, links, selection chrome, active tab icon/label |
| `STColor.primaryPressed` | Pressed/deeper primary (derived from #008BFF) |
| `STColor.primarySubtle` | Soft selected pill / whisper fills (not a solid blue block) |
| `STColor.destructive` | Destructive only |

Do **not** use system blue, green, or ad-hoc hex for primary actions. Destructive stays red.

`STHomeAtmosphere` / `.stTabRootAtmosphere()` — Quiet Pocket hero wash on **all tab roots** (Home, Search, Cleanup, Settings). Scrolls with the title area; fades before lower content. Tunables: `STHomeAtmosphereTokens`.

`STOnboardingAtmosphere` — related full-step wash for onboarding (deeper cool + leading bias; fixed full-screen). Tunables: `STOnboardingAtmosphereTokens`.

### Shadow (`STShadow` + view modifiers)

One calm elevation language — **whisper-soft**, barely noticeable (Settings / Photos / Journal). Hairline strokes carry definition; shadows never dominate.

| Token / modifier | Use |
|------------------|-----|
| `.stSurfaceShadow()` | Cards, pockets, settings groups, onboarding containers |
| `.stPocketShadow()` / `.stCardShadow()` | Aliases → surface |
| `.stSearchFieldShadow()` | Search field (lighter than surface) |
| `.stPeekShadow()` | Screenshot peeks |
| `.stBadgeShadow()` | Emoji chip |

Do **not** declare one-off shadows in feature screens.

### Typography (`STTypography`)
greeting · aiLine · sectionTitle · pocketTitle · pocketMeta · rowTitle · rowMeta · search · button · tabLabel · empty*

### Motion (`STMotion` + `STCardPressStyle`)
pressScale **0.985** · pressDuration **0.18s** · toast spring appear · Reduce Motion aware

### Toast (`STToast`)
Dark charcoal/material capsule · `checkmark.circle.fill` · floats above system tab bar · **not** Quiet Pocket white  
Optional trailing action (standard: **Undo** in `STColor.primary` `#008BFF` on a whisper capsule)  
Hold: ~2.5s informational · ~5s with Undo · never full-width (`toastMaxWidth` / `toastActionMaxWidth`)  
Only expose Undo when restoration is genuinely possible (Sprint 2 mock store ≠ future PhotoKit)

---

## Signature component: `ContextCollectionPocketView`

Compact document-sleeve pocket (D-014–D-018):

1. Screenshots **behind** the folder panel (~40% visible)  
2. Exactly **3** large fanned peeks (center highest)  
3. Soft white rounded folder + Apple shadow + subtle lip  
4. `STEmojiBadge` top-left; title + metadata **bottom-left**; empty middle  
5. No scrapbook chrome  

Aliases: `ContextCollectionCard`, `ContextCollectionPocket`

---

## Component inventory

| Component | Purpose |
|-----------|---------|
| `ContextCollectionPocketView` | Signature collection folder |
| `STNewCollectionTile` | Quiet Home grid create action (last cell) |
| `STHomeAtmosphere` | Soft cool-blue Home hero wash (background only) |
| `STEmojiBadge` | Single emoji chip |
| `PeekingStackCollage` / `ScreenshotPreview` | Mock peeks → Photos thumbs later |
| `STGreetingHeader` | Home greeting + rotating approved subtitle (`STHomeCopy`) |
| `STNeedsReviewCard` | Compact Needs Review entry (peeks + copy; hidden when empty; no sparkles/Review CTA) |
| `STSectionHeader` | Secondary screen headers |
| `STSearchField` | Quiet search |
| `STPage` / `STPageContainer` | Page chrome |
| `STPrimaryCard` (`STCard`) | Generic soft card |
| `STPrimaryButton` / `STSecondaryButton` | CTAs |
| `STEmptyState` | Empty / error |
| `STScreenshotGridItem` | 3-column gallery thumbnail |
| `STScreenshotLayoutPicker` | ~~removed~~ — Collection Detail is grid-only |
| Native `TabView` (`RootView`) | System Liquid Glass tab bar — see D-010 |
| `STToast` / `STToastHost` | Dark floating snackbar; optional Undo action (primary blue) |
| `STCardPressStyle` | Press interaction |

### Tab bar — native `TabView` (locked behavior)

- **Implementation:** SwiftUI `TabView` in `RootView` — not a custom glass dock  
- **Tabs (IA order):** Home · Search · Cleanup · Settings — SF Symbols + labels  
- **Accent:** `.tint(STColor.primary)` → `#008BFF` selected treatment; inactive = system secondary  
- **Liquid Glass:** system-owned on current iOS (floats above content; content can show through)  
- **Safe area:** system positioning above Home indicator — no hardcoded bottom breathing  
- **Details:** `.toolbar(.hidden, for: .tabBar)` on pushed routes  
- **Not used:** custom drag, `Tab(role: .search)` (would reorder Search), `tabBarMinimizeBehavior` (see D-010)  
- **A11y:** system VoiceOver / hit targets / Reduce Motion / Reduce Transparency  

**Deferred (Sprint 2+):** FacetChip, EntityChip, ConfirmationSheet, MergeContextsSheet, OrganizationProgress, hero shared-element.

---

## How future screens reuse this

1. Wrap content in `STPage` (or match `STSpacing.page` + `STColor.background`).  
2. Use `STTypography` / `STColor` — never ad-hoc fonts/colors for hierarchy.  
3. Use `STPrimaryCard` or `ContextCollectionPocketView` — don’t reinvent shadows/radii.  
4. Use `STCardPressStyle` for tappable surfaces.  
5. Rely on native `TabView` bottom safe-area insets — do not re-add large manual dock clearance.  
6. Swap `ScreenshotPreview` for Photos thumbnails in Sprint 4 without changing pocket layout.

---

## Accessibility

- Dynamic Type via semantic fonts  
- VoiceOver: “Japan Trip, 12 screenshots”  
- 44pt targets on tabs / rows (system tab bar)  
- Reduce Motion respected on press + toast  
- Tab bar: Reduce Transparency adapts via system Liquid Glass  
