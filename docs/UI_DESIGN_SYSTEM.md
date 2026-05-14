# Marathon UI Design System

The visual language of Marathon Shell: a BB10-inspired, OLED-first dark theme optimised for 60fps on ARM embedded hardware (Pi 4, HackBerry Pi, Droidian phones).

This document mirrors the code in `marathon-ui/`. Where it disagrees with the code, the code wins; update this file.

## Philosophy

- **OLED-black background, near-black surfaces.** Pure `#040404` (`bb10Black`) at the floor, six steps up to `#353536`.
- **Teal accent.** `#00bfa5` (`marathonTeal`) plus a dark/bright/glow ladder. Used sparingly — primary action, focus indicator, active tab.
- **Depth from borders, not shadows.** Every elevated surface has an outer dark border (shadow edge) and inner light border (highlight). FBO-based drop shadows are banned per the performance rules below.
- **Sharp by default.** Border radius is 2–8px scaled. 999 reserved for pills/circles.
- **Spring physics over linear curves** for press/hover state changes; explicit Bezier curves elsewhere.
- **Opaque rendering.** Alpha-blended pixels are 2–3× more expensive on the target GPUs. Translucency is the exception (overlays, ripples, hover tints).

## Layering

The codebase has two color systems that coexist, intentionally:

- **`MColors`** — semantic names (`background`, `surface`, `elevated`, `accent`, `text`, `border…`, glass tints). What apps use day-to-day.
- **`MElevation`** — numeric `getSurface(0–5)` / `getBorderOuter(0–5)` / `getBorderInner(0–5)` for components that take an `elevation:` prop and need to interpolate.

Components that nest may use either — `MCard`, `MLayer`, `MSettingsListItem` go through `MElevation`; everything else picks a `MColors` semantic surface. They are not interchangeable: `MColors.surface` (`#0d0d0e`) is between `MElevation` levels 1 and 2.

## Design tokens

All values are from `marathon-ui/Theme/`. `MSpacing`, `MRadius`, `MTypography` multiply their base by `Constants.scaleFactor` (singleton in `MarathonOS.Shell`), so the numbers below are the base before scaling.

### Colors (`Theme/MColors.qml`)

**Base palette (BB10 grays):**

| Token | Hex |
|---|---|
| `bb10Black` | `#040404` |
| `bb10Deep` | `#070707` |
| `bb10Surface` | `#0d0d0e` |
| `bb10Elevated` | `#161718` |
| `bb10Card` | `#1a1b1c` |

**Semantic aliases:** `background = bb10Black`, `surface = bb10Surface`, `elevated = bb10Elevated`, `backgroundLight = bb10Elevated`, `textInverse = bb10Black`.

**Accent (teal ladder):**

| Token | Hex |
|---|---|
| `marathonTealDarkest` | `#006b5d` |
| `marathonTealDark` | `#00897b` |
| `marathonTeal` (= `accent`) | `#00bfa5` |
| `marathonTealBright` (= `accentBright`) | `#1de9b6` |
| `marathonTealGlow` | `#5dffdc` |

Plus tinted overlays for hover/press/glow gradients (`marathonTealHoverGradient` 3%, `marathonTealPressGradient` 12%, `marathonTealGlowTop/Mid/Bottom` 18/10/2%, `marathonTealBorder` 35%, `marathonTealBorderHover` 40%).

**Text:**

| Token | Hex |
|---|---|
| `textPrimary` (= `text`) | `#f5f5f5` |
| `textSecondary` | `#6a6a6a` |
| `textTertiary` | `#4a4a4a` |
| `textHint` | `#2a2a2a` |
| `textOnAccent` | `#ffffff` |

**Status:**

| Token | Hex |
|---|---|
| `success` / `successDim` | `#10B981` / `#059669` |
| `warning` / `warningDim` | `#F59E0B` / `#D97706` |
| `error` / `errorDim` | `#EF4444` / `#DC2626` |
| `info` / `infoDim` | `#3B82F6` / `#2563EB` |

**Glass surfaces** (high-opacity translucents used for system chrome):

| Token | Value |
|---|---|
| `glassTitlebar` | `rgba(13,13,14, 0.72)` |
| `glassTabbar` | `rgba(16,16,17, 0.78)` |
| `glassActionbar` | `rgba(11,11,12, 0.82)` |
| `glassHeader` | `rgba(18,18,19, 0.85)` |

**Borders / interaction:**

| Token | Value |
|---|---|
| `borderGlass` (= `border`) | `rgba(1,1,1, 0.08)` |
| `borderSubtle` | `rgba(1,1,1, 0.05)` |
| `borderDark` | `rgba(0,0,0, 0.7)` |
| `highlightSubtle` / `highlightMedium` | `rgba(1,1,1, 0.03)` / `0.06` |
| `hover` | `rgba(1,1,1, 0.04)` |
| `pressed` | `rgba(0,0,0, 0.1)` |
| `ripple` | `rgba(0, 0.749, 0.647, 0.12)` (teal-tinted, not white) |
| `overlay` / `overlayLight` | `rgba(0,0,0, 0.85)` / `0.7` |
| `shadowDefault` / `shadowStrong` / `shadowHeavy` | `rgba(0,0,0, 0.4)` / `0.6` / `0.7` |

There are also numbered overlay helpers (`whiteOverlay02…40`, `blackOverlay15/40`) for cases where you'd otherwise inline `Qt.rgba`.

### Elevation (`Theme/MElevation.qml`)

Functions, not constants — pass a level 0–5.

| Level | `getSurface` | `getBorderOuter` | `getBorderInner` | Use |
|---|---|---|---|---|
| 0 | `#040404` | `rgba(0,0,0,0.90)` | `rgba(1,1,1,0.00)` | Background, base |
| 1 | `#0a0a0b` | `rgba(0,0,0,1.00)` | `rgba(1,1,1,0.04)` | Cards, panels |
| 2 | `#121213` | `rgba(0,0,0,1.00)` | `rgba(1,1,1,0.06)` | Raised cards |
| 3 | `#1c1c1d` | `rgba(0,0,0,0.95)` | `rgba(1,1,1,0.09)` | Modals, sheets |
| 4 | `#282829` | `rgba(0,0,0,0.90)` | `rgba(1,1,1,0.12)` | Floating menus |
| 5 | `#353536` | `rgba(0,0,0,0.85)` | `rgba(1,1,1,0.15)` | Tooltips, popovers |

Default fallback (any other level) returns level-2 values.

### Motion (`Theme/MMotion.qml`)

**Duration tokens (ms):**

| Token | ms | Aliases |
|---|---|---|
| `instant` | 0 | — |
| `fast` | 150 | `xs` |
| `normal` | 200 | `sm` |
| `slow` | 300 | `md` |
| `slower` | 400 | `lg` |
| `micro` | 80 | — |
| `quick` | 160 | — |
| `moderate` | 240 | — |

**Spring physics:**

| Token | Spring / Damping | Use |
|---|---|---|
| Light | `1.5` / `0.15` | Bouncy — cards, buttons |
| Medium | `2.0` / `0.25` | Balanced — sheets, modals |
| Heavy | `3.0` / `0.4` | Firm — toggles, sliders |

`epsilon: 0.01` for spring stopping threshold.

**Easing (Bezier control points):**

| Token | Curve |
|---|---|
| `easingStandard` | `[0.2, 0, 0.2, 1]` |
| `easingDecelerate` | `[0, 0, 0.2, 1]` |
| `easingAccelerate` | `[0.4, 0, 1, 1]` |
| `easingSpring` | `[0.34, 1.56, 0.64, 1]` |

Each is exposed as a pair (`easing<Name>` = `Easing.Bezier` enum, `easing<Name>Curve` = `[c1, c2, c3, c4]`) for `Behavior on … { NumberAnimation { easing.type: …; easing.bezierCurve: … } }`.

**Stagger (ms between siblings):** `staggerMicro 20`, `staggerShort 50`, `staggerMedium 80`, `staggerLong 120`.

**Page transitions:** `pageParallaxOffset 0.3`, `pageScaleOut 0.92`.

**Ripple:** `rippleDuration = slow (300)`, `rippleMaxRadius 2.5`, `rippleOpacity 0.12`.

**Flick physics:** `flickDecelerationFast 8000`, `flickVelocityMax 5000`, `touchFlickDeceleration 25000`, `touchFlickVelocity 8000`.

### Spacing (`Theme/MSpacing.qml`) — base × `Constants.scaleFactor`

| Token | px (base) |
|---|---|
| `xs` | 5 |
| `sm` | 10 |
| `md` | 16 |
| `lg` | 20 |
| `xl` | 32 |
| `xxl` | 40 |

**Touch targets** (HIG-aligned, scaled): `touchTargetMin 45`, `touchTargetSmall 60`, `touchTargetMedium 70`, `touchTargetLarge 90`.

### Radius (`Theme/MRadius.qml`) — scaled

`none 0`, `sm 2`, `md 4`, `lg 6`, `xl 8`, `pill 999` (= `circle` = `full`).

Default for most components is `md` (4). Pills (badges, page indicators) use 999.

### Typography (`Theme/MTypography.qml`) — scaled

- **Families:** `fontFamily = "Slate"`, `fontFamilyMono = "JetBrains Mono"` (alias `fontMonospace`).
- **Sizes:** `XSmall 12`, `Small 14`, `Body 16`, `Large 18`, `XLarge 24`, `XXLarge 32`, `Display 40`, `Huge 48`, `Gigantic 96`.
- **Weights:** `Light`, `Regular/Normal`, `Medium`, `DemiBold`, `Bold`, `Black` (mapped to `Font.*`).

### Responsiveness (`Core/MBreakpoints.qml`, `Core/MResponsive.qml`)

`MBreakpoints` (singleton) defines breakpoints in pixels — **not scaled**, since they describe physical/viewport dimensions:

| Token | px | Helpers |
|---|---|---|
| `xs` | 320 | `isXS()`, `atLeastXS()` |
| `sm` | 576 | `isSM()`, `atLeastSM()` |
| `md` | 768 | `isMD()`, `atLeastMD()` |
| `lg` | 1024 | `isLG()`, `atLeastLG()` |
| `xl` | 1280 | `isXL()`, `atLeastXL()` |
| `xxl` | 1536 | `isXXL()`, `atLeastXXL()` |

`MResponsive` is a non-singleton wrapper instantiated per screen/page. Set `screenWidth`, read `currentBreakpoint`, `isMobile/isTablet/isDesktop`, or call `value({xs: a, sm: b, ...})` / `columns({...})` for token-picking.

## Module map

QML modules registered via `qt6_add_qml_module` under `marathon-ui/`:

| URI | Contents |
|---|---|
| `MarathonUI.Theme` | `MColors`, `MElevation`, `MMotion`, `MSpacing`, `MRadius`, `MTypography` (all singletons) |
| `MarathonUI.Core` | `MButton`, `MIconButton`, `MCircularIconButton`, `MImageButton`, `MLabel`, `MTextInput`, `MTextArea`, `MContainer`, `MAppIcon`, `Icon`, `MDateTimePicker`, `MEmptyState`, `MGrid`, `MBreakpoints` (singleton), `MResponsive` |
| `MarathonUI.Containers` | `MApp`, `MCard`, `MFormCard`, `MFormField`, `MLayer`, `MListItem`, `MListTile`, `MPage`, `MPanel`, `MPullToRefresh`, `MScrollView`, `MSection`, `MSectionHeader`, `MSettingsListItem`, `MSwipeDelegate` |
| `MarathonUI.Controls` | `MCheckbox`, `MComboBox`, `MDropdown`, `MRadioButton`, `MRadioGroup`, `MSlider`, `MToggle` |
| `MarathonUI.Effects` | `MHaptics`, `MRipple` |
| `MarathonUI.Feedback` | `MActivityIndicator`, `MBadge`, `MProgressBar` |
| `MarathonUI.Lists` | `MDivider` |
| `MarathonUI.Modals` | `MConfirmDialog`, `MModal`, `MSheet` |
| `MarathonUI.Navigation` | `MActionBar`, `MAppRouter`, `MBottomBar`, `MNavigationPane`, `MPageIndicator`, `MSwipeView`, `MTabBar`, `MTopBar` |

`MarathonUI.Theme` is self-contained. `Core`/`Containers`/etc. import both `MarathonUI.Theme` and `MarathonOS.Shell` (for `Constants.scaleFactor`); MarathonUI is not usable standalone without the shell's `Constants` singleton on the QML import path.

`MAppRouter` is in `MarathonUI.Navigation` despite being non-visual: it's a `StackView`-driven route controller (`pushRoute(name, props)` / `popRoute()`, `routeMap`, deep-link integration with `NavigationRouter`). The location follows platform convention — iOS UIKit groups `UINavigationController` under Navigation, AndroidX puts the Navigation Component under `androidx.navigation` — so "routing primitive belongs in Navigation" is the canonical reading, not a misfile.

### Press feedback (state-of-the-art reference)

The scale + spring + haptic pattern below is consistent with **Material 3 Expressive** (Google I/O 2025), which moved away from flat color-only press states to springy scale + haptic rumble across primary controls, and with iOS HIG's long-standing scale-on-press for buttons. Earlier Marathon documentation suggested "color-only, no scale, BB10-strict" — that guidance is **deprecated**; the BB10 aesthetic is preserved via sharp corners, dual-border depth, the teal palette, and OLED-black surfaces, not by removing motion.

## Component conventions

### Press feedback

Marathon UI buttons / cards / interactive surfaces use **scale + color shift + haptic + (sometimes) ripple**. The typical pattern:

```qml
scale: pressed ? 0.96 : 1.0
Behavior on scale {
    SpringAnimation { spring: MMotion.springMedium; damping: MMotion.dampingMedium; epsilon: MMotion.epsilon }
}
onPressed: MHaptics.light()
```

Press-scale conventions used in current code:

| Component | Scale on press |
|---|---|
| `MButton`, `MCircularIconButton`, `MImageButton`, `MCard`, `MActionBar`, `MTabBar` action | 0.96 |
| `MIconButton`, `MCheckbox`, `MRadioButton` | 0.92 |
| `MSlider` handle | 1.15 (grows on grab) |
| `MModal`, `MConfirmDialog`, `MSheet`, `MComboBox`/`MDropdown` menu | enter at 0.9–0.95, spring to 1.0 |

### Depth (dual border)

```qml
Rectangle {
    color: MElevation.getSurface(elevation)
    border.color: MElevation.getBorderOuter(elevation); border.width: 1
    Rectangle {
        anchors.fill: parent; anchors.margins: 1
        color: "transparent"
        border.color: MElevation.getBorderInner(elevation); border.width: 1
    }
}
```

### Haptics

`MHaptics` (singleton in `MarathonUI.Effects`) is the QML entry point used by `marathon-ui` components, which must not depend on shell-specific types. It exposes `light()`, `medium()`, `heavy()`, `selection()`, `success()`, `error()`, `warning()`, `impact(intensity, duration)`, and forwards everything to its `backend` property — a `QtObject` injected once by the shell at startup. Use `light()` for taps, `medium()` for swipe thresholds, `heavy()` / `error()` for destructive confirmations.

The backend is the C++ `HapticManager`, registered as a QML singleton on `MarathonOS.Shell 1.0` (per CODING_RULES C11 — no context properties). Shell-side QML can call `HapticManager.light()` directly; reusable `marathon-ui` components must go through `MHaptics` so they stay decoupled from the shell module.

### Ripple

`MRipple` is an opt-in overlay. `MCard` uses it; buttons typically don't (scale + haptic is sufficient and cheaper). Trigger from the touch point:

```qml
MRipple { id: ripple }
TapHandler { onTapped: (e) => ripple.trigger(Qt.point(e.position.x, e.position.y)) }
```

## Performance rules

These are the rules the rendering pipeline depends on. Violating them is detected at review.

1. **Opaque first.** All fills are fully opaque except for: modal overlays (`MColors.overlay`, 85%), glass chrome (`glass*` tokens, 72–85%), ripple (12%), accent tints. Don't introduce new 90–95% alpha "for the look."
2. **No `layer.enabled`** except for SVG colorisation in `Icon.qml`. No `FastBlur` / `GaussianBlur` anywhere. `MultiEffect` is permitted **only on transient popup surfaces** — `MModal`, `MSheet`, `MConfirmDialog`, `MComboBox` / `MDropdown` menus. Rationale: Qt 6.5+'s `MultiEffect` combines multiple effects into a single shader pass (unlike the chained-FBO `QtGraphicalEffects` of Qt 5) and is the official replacement; for a dropdown that mounts for ~200ms and unmounts, one shader pass is acceptable. Everywhere else (cards, status bar, app grid, list rows, lock screen, anything persistent), depth uses the dual-border technique.
3. **No `clip: true` unless overflow is real.** Stencil ops are expensive on Mali/Broadcom GPUs.
4. **No infinite animations on hidden items.** Gate `running` on visibility (`running: lockScreen.visible`). See `CODING_RULES.md` C8 — this is a regression we paid for once.
5. **Spring animations on `scale`/`opacity` only**, not on `width`/`height` (triggers layout recalculation).
6. **ListView delegates use `cacheBuffer` and `reuseItems`.** Anything longer than ~20 items must be a delegate-recycling view, not a `Column`/`Row`.
7. **Tokens, never inline hex.** Per `CODING_RULES.md` C12: colors, fonts, spacings, radii, durations live in the theme singletons. No inline `#1A1A1A` in 30 components.

## Migration notes

For files predating this design system you may see:

- `import "../components/ui"` and `Button { … }` — migrate to `import MarathonUI.Core` and `MButton { … }`.
- `Constants.animationFast` — equivalent to `MMotion.fast`. Prefer `MMotion` going forward.
- Inline `#0F0F0F` / `#1A1A1A` — these match neither `MColors` nor `MElevation`. Replace with the nearest `MColors.surface*` or `MElevation.getSurface(level)`.

## Testing

```bash
# Run with QML profiler attached
QML_PROFILER=1 ./build/shell/marathon-shell-bin

# Overdraw + batches visualisers (catch alpha-stacking and tiny draws)
QSG_VISUALIZE=overdraw ./run.sh
QSG_VISUALIZE=batches  ./run.sh

# Texture memory + scene-graph info
QSG_INFO=1 ./run.sh
```

Targets: 60fps on Pi 4, <100ms gesture response, <500ms QML app launch, <1s native app launch, <100MB RSS for the UI process.

## Status

- Target hardware: Raspberry Pi 4 (ARM Cortex-A72), HackBerry Pi, Droidian phones.
- Source of truth: `marathon-ui/Theme/*.qml`. Update this doc whenever those files change.
