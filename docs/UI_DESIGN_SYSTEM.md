# Marathon Design System — Baseline

The canonical reference for Marathon's fluid design language. This is the
load-bearing document for the dev cycle: every new component, motion
choice, chrome treatment, or gesture wires back here.

When this doc disagrees with the code: **the code wins** — update this
file. When this doc disagrees with someone's opinion in a PR review: the
doc wins until the next baseline revision (which is a Bigger Decision
than the PR).

Source of truth for token values: `marathon-ui/Theme/*.qml`. Numbers
quoted here are the base before `Constants.scaleFactor`.

---

## 0. Charter

Marathon is a Qt6/QML mobile shell + in-process Wayland compositor for
the Librem 5, Raspberry Pi 5, and any pmOS-class Linux phone. Its design
mandate isn't to ship a Linux phone that's *adequate*; it's to ship one
people pick up at the table and ask about. The bar to beat is iOS 18+,
Android 16 (Material 3 Expressive), and OneUI 7 — not phosh/Plasma
Mobile.

Three non-negotiable commitments structure the system:

1. **Coherence over surface variety.** One color, one motion ladder, one
   chrome language across lockscreen, home, apps, modals, sheets,
   notifications. A user should never wonder if a screen "belongs" to
   Marathon.
2. **Motion is functional, not decorative.** Every microinteraction
   makes the user's mental model correct. No animation that exists just
   because animations are nice. Every spring + curve is selected from a
   role-tagged table (`MMotion.roles`), not freehanded.
3. **In-process compositor is a feature.** Shell + compositor + every
   app surface live in one Qt scenegraph. That gives us iOS-grade
   sub-frame chrome+app coherence that wlroots-based stacks (phosh,
   gnome-shell) physically cannot do. The system is designed to *use*
   that — not to hide it for portability.

---

## 1. The 2026 world-class mobile bar — distilled

What "sensational" looks like in 2025-2026, condensed from iOS 18+,
Material 3 Expressive (Google I/O 2025), OneUI 7, and the post-mortems
of webOS, BB10, and Windows Phone Metro. Each row is a principle plus
how Marathon expresses it.

| Principle | What the best mobile OSes do | Marathon's realisation |
|---|---|---|
| **Spring physics over ease curves** | iOS rubber-banding, M3 Expressive's 4-rung stiffness ladder, OneUI 7 micro-springs | `MMotion.stiffness{High,Medium,Low,VeryLow}` + spatial/effects damping split. `MMotion.roles` table tags every microinteraction with a role, not a duration |
| **Predictive gestures** | Android predictive-back, iOS edge-swipe with parallax | `MarathonNavBar.backProgress` drives `appWindowContainer.scale 1.0→0.9` + opacity fade past `MMotion.backFadeThreshold` (0.35). Pill left-drag is the primary back affordance |
| **Glass / blur with discipline** | iOS 26 Liquid Glass, M3 Expressive's tinted scrim, OneUI 7's translucent shade | `MGlass` primitive: `ShaderEffectSource + MultiEffect` blur of the live framebuffer behind the chrome. `MBlur` role map (`chrome=lg`, `sheet=lg`, `dropdown=sm`, `halo=sm`, `hairline=xxs`). Always opt-out via `MMotion.reduceBlur` |
| **Restraint at the edge** | iOS's "everything is the same color but slightly different temperature", BB10's near-black palette | OLED-first dark theme, `#040404` floor, six elevation steps up to `#353536`. Teal accent (`#1de9b6` bright) appears only on the active path: focused control, current tab, primary action |
| **Microcoherence (sub-frame)** | Apple's app-open animation that paints chrome + app body as one surface; impossible on multi-process compositors | In-process scenegraph means a status-bar reveal, a navbar pill morph, and an app-window scale can land in one frame with zero IPC. We design for this — see §7 |
| **Live activities / persistent surfaces** | Dynamic Island, iOS Live Activities, Android persistent notifications | NowBar (planned): an always-visible micro-surface for active calls, media, navigation, timers. One canonical promotion target, not per-feature widgets |
| **Tactile coupling** | iOS Taptic Engine, OneUI 7 micro-rumbles on every flick | `MHaptics` singleton; every gesture threshold + state-change has a haptic tier (`light/medium/heavy/selection/success/error`). Springs and haptics fire together, never apart |
| **Accessibility as primitive** | iOS Reduce Motion + Reduce Transparency (separate toggles), Android Talkback-tested per release | `MMotion.reduceMotion` + `MMotion.reduceBlur` + `MMotion.translucencyLevel` (0..1 slider). Every component routes through `dur()`/`ease()`/blur token APIs so the toggles are uniform |
| **Density that scales with palm size** | iOS Display Zoom, Android display density | `Constants.scaleFactor` multiplies `MSpacing`, `MRadius`, `MTypography` from a single DPI signal. Breakpoint helpers in `MBreakpoints`/`MResponsive` for phone/tablet/desktop split |

The non-obvious shared idea: **the best mobile OSes feel alive without
ever feeling decorative**. Every spring serves a perception goal
(arriving, returning, settling, attending). Marathon's mandate is the
same — and the role-based motion table (§4) is how we enforce it.

---

## 2. Identity

### 2.1 Color

The Marathon palette is OLED-first dark with a single saturated accent.
There is no light theme — the surface ladder + accent IS the identity.

**Surface ladder (`MColors` + `MElevation`):**

| Step | Token | Hex | Use |
|---|---|---|---|
| 0 (floor) | `bb10Black` / `background` | `#040404` | Screen background, OLED-true black |
| 0.5 | `bb10Deep` | `#070707` | Lockscreen tint, status-bar inactive |
| 1 | `bb10Surface` / `surface` | `#0d0d0e` | Cards, panels, list rows |
| 2 | `bb10Elevated` / `elevated` | `#161718` | Raised cards, hovered surface |
| 3 | `bb10Card` | `#1a1b1c` | Modals, sheets, popovers |
| 4 | — | `#282829` | Floating menus, picker overlays |
| 5 | — | `#353536` | Tooltips, transient popovers |

Numeric access via `MElevation.getSurface(0..5)`, `getBorderOuter(level)`,
`getBorderInner(level)`. Use semantic `MColors` names in everyday QML;
reach for `MElevation` when a component takes an `elevation:` prop and
needs to interpolate (`MCard`, `MLayer`, `MSettingsListItem`).

**Accent (teal ladder):**

| Token | Hex | Role |
|---|---|---|
| `marathonTealDarkest` | `#006b5d` | Pressed accent surfaces |
| `marathonTealDark` | `#00897b` | Disabled accent state |
| `marathonTeal` / `accent` | `#00bfa5` | Default accent (icons, indicators) |
| `marathonTealBright` / `accentBright` | `#1de9b6` | **Primary brand mark, focus glow** |
| `marathonTealGlow` | `#5dffdc` | Halo / pulse highlights |

Plus tinted overlays (`marathonTealHover/Press/Glow*`, border tints
35-40%) — never inline `Qt.rgba()` with the teal; reach for the named
overlay token.

**Status colors** (mailbox indicators, toast banners, validation):
`success #10B981`, `warning #F59E0B`, `error #EF4444`, `info #3B82F6`
(each with a `*Dim` sibling for borders/secondary fills).

**Text ladder:**
`textPrimary #f5f5f5` → `textSecondary #6a6a6a` → `textTertiary #4a4a4a`
→ `textHint #2a2a2a` → `textOnAccent #ffffff`. Three secondary tiers
sounds like a lot; on OLED with 720x1440 it's the difference between
"label", "metadata", and "placeholder" being legible without being loud.

### 2.2 Typography

- **Slate** — UI sans (variable weight, geometric, condensed for status
  chrome). Aliased as `MTypography.fontFamily`.
- **JetBrains Mono** — monospace, code/timestamps/PIN/secret reveal.
  `fontFamilyMono` / `fontMonospace`.

Scale (base px, multiplied by `scaleFactor`):
`XSmall 12 · Small 14 · Body 16 · Large 18 · XLarge 24 · XXLarge 32 ·
Display 40 · Huge 48 · Gigantic 96`.

Weights map to `Font.*` (`Light`, `Regular`, `Medium`, `DemiBold`,
`Bold`, `Black`). Heading hierarchy uses DemiBold/Bold; body always
Regular; chrome (clock, badges) uses Medium for the small-but-legible
sweet spot.

### 2.3 Geometry

**Spacing** (`MSpacing`, base px × scaleFactor):
`xs 5 · sm 10 · md 16 · lg 20 · xl 32 · xxl 40`. Default gap between
related items is `sm`; between unrelated sections, `lg`. The grid is
opinionated — designers don't get to pick "13".

**Radii** (`MRadius`): `none 0 · sm 2 · md 4 · lg 6 · xl 8 · pill 999`.
Default is `md`. The whole system is **sharp by default** — pills are
reserved for the literal pill shape (badges, page indicators, the
nav-bar pill itself). This is where Marathon visually diverges from
iOS's pervasive rounded-rect language.

**Touch targets**: `touchTargetMin 45 · Small 60 · Medium 70 · Large 90`.
Even a status-bar tap zone uses `Min` — never less, regardless of icon
size.

### 2.4 Density grid

The shell ships at 720×1440 on the L5 and is laid out around a 24-column
soft grid with `lg` (20 px) gutters. Cards span 22 columns (the canonical
content width); status chrome occupies the full 24. Apps don't get a
say in the column count — they get `MPage`, which enforces it.

---

## 3. Surfaces & depth

Depth comes from **two borders and a delta in surface lightness**, not
from drop shadows. FBO-based shadows (`FastBlur` + `OpacityMask`) are
banned on the etnaviv GLES2 path — they collapse the L5 to 2 fps. (See
the `MARATHON_LAYER_SAMPLES` env / Etnaviv MSAA trap memory.)

The canonical depth recipe:

```qml
Rectangle {
    color: MElevation.getSurface(elevation)
    border.color: MElevation.getBorderOuter(elevation); border.width: 1
    Rectangle {                                  // inner highlight
        anchors.fill: parent; anchors.margins: 1
        color: "transparent"
        border.color: MElevation.getBorderInner(elevation); border.width: 1
    }
}
```

Two 1 px borders, two SDF-friendly draws, zero shaders. Reads as depth
on OLED because the outer border crushes to absolute black while the
inner highlight catches the panel's micro-emission.

**`MultiEffect` exception.** Qt 6.5+'s `MultiEffect` (one shader pass,
not the chained-FBO `QtGraphicalEffects` of Qt 5) is permitted only for
*transient* surfaces that mount and unmount inside ~300 ms: `MModal`,
`MSheet`, `MConfirmDialog`, `MComboBox`/`MDropdown` menus. Never on
persistent chrome, cards, list rows, or status bar — those use `MGlass`
(see §7) or the dual-border recipe.

---

## 4. Motion

Motion is the system's nervous system. Every interactive surface,
transition, settle, and pulse picks a **role** from `MMotion.roles` and
reads its physics from there. Roles encode *meaning* — "a tap settling",
"a panel pulling down" — not raw numbers. Tuning the system means
editing the table, not 200 call sites.

### 4.1 Role table (`MMotion.roles`)

| Role | When | Duration | Stiffness (spatial) | Damping (spatial) |
|---|---|---|---|---|
| `microPress` | Press-down haptic, scale to 0.97 | 80 ms | High (4.0) | Critical (1.0) |
| `press` | Same as microPress, distinct semantic for press-hold | 80 ms | High | Critical |
| `tap` | Press-release, chip toggle (default if role missing) | 120 ms | Medium (2.0) | 0.35 |
| `hover` | State colour, focus ring fade | 150 ms | Medium | 0.30 |
| `nav` | Page **push** in `MStackView`, tab change | 220 ms | VeryLow (0.5) | 0.25 |
| `hero` | Hero / cross-fade page transitions | 320 ms | VeryLow | 0.18 |
| `predictiveBack` | Back-gesture in-flight + commit | 220 ms | Low (1.0) | Critical |
| `modal` | Dialog / sheet open / close | 240 ms | Low | 0.22 |
| `panel` | QS shade pull, status reveal | 300 ms | Low | 0.20 |
| `sheet` | Full-bleed sheet (settings deep page) | 320 ms | Low | 0.20 |
| `entrance` | List-item stagger, app-grid first-paint | 220 ms | Low | 0.25 |
| `pulse` | Infinite attention loops (chevron, ringing) | 1200 ms | Low | 0.15 |

**Two-family damping.** Each role splits its physics across spatial
(position, size, rotation) and effects (color, opacity). Spatial
damping is underdamped (springy "alive" feel). Effects damping is
always `dampingCritical` — a button background that overshoots to a
darker shade looks broken.

```qml
SpringAnimation {
    spring: MMotion.stiffnessSpatialFor("nav")
    damping: MMotion.dampingSpatialFor("nav")
    epsilon: MMotion.epsilon
}
ColorAnimation {
    duration: MMotion.durationFor("hover")
    // colour is an effect; never use spatial damping here
}
```

### 4.2 Page transitions (`MStackView`)

Push and pop deliberately have **different stiffness**. A new page
arriving is grand and deliberate (`pushStiffness = stiffnessSpatialFor("nav") = VeryLow`,
~600 ms grand iOS-style arrival). Going back is snappy and decisive
(`popStiffness = stiffnessMedium`, ~300-500 ms). Both critical-damped
on pop — there's no "did it land?" ambiguity going back.

Parallax: the outgoing page lags the incoming one at
`pageParallaxOffset = 0.3` (30% of travel). iOS uses ~25-30%; that
number IS the iOS-feel anchor.

### 4.3 Predictive back (Android M3 Expressive spec)

Marathon's predictive-back honours the published Android tokens
verbatim because there's no reason to be clever:

- Exit screen: `1.0 → 0.9` scale
- Enter screen: `1.10 → 1.00` scale (subtle overshoot in)
- Fade threshold: 35% of progress
- Shared-element shift: `max(0, width/20 - 8 dp)` per-axis, with 8 dp
  edge clamp
- Easing: `(0.1, 0.1, 0.0, 1)`

In the shell, `MarathonNavBar.backProgress` (0..1) tracks the leftward
drag distance against `width * 0.55`. `MarathonShell` binds
`appWindowContainer.scale` and `opacity` through those tokens. Spring-
back on cancel is gated on `!navMouseArea.pressed` so the drag itself
tracks the finger 1:1 — the spring only fires on cancel.

### 4.4 Reduce motion

`MMotion.reduceMotion` is the central toggle. Bound at app startup from
GNOME (`org.gnome.desktop.interface enable-animations`) or KDE
(`KAccessibilityCommon.skipFancyEffects`). When true:

- `dur(token)` returns `micro` (80 ms)
- `ease(token)` returns `Easing.OutQuad` (no overshoot)
- `MMotion.gate(cond)` returns false for infinite loops

Every animation goes through these helpers or the role accessors. No
freehand `NumberAnimation { duration: 300 }` — the audit catches them.

### 4.5 Reduce blur / translucency level

Companion to reduce-motion. `MMotion.reduceBlur` switches `MGlass` to
an opaque chrome rendering. `MMotion.translucencyLevel` (0..1) is the
soft knob Apple shipped as the iOS 27 translucency slider — multiplies
blur radius + tint opacity proportionally. At 0.0 it collapses to
reduce-blur; at 1.0 the chrome gets full effect.

---

## 5. Gestures & touch

The pill at the bottom of `MarathonNavBar` is the **single touchpoint
for system navigation**. Its semantic surface area:

| Gesture | Effect |
|---|---|
| Tap | (nothing — it's a status affordance, not a button) |
| Short swipe up | Minimize app / dismiss keyboard / dismiss search |
| Long swipe up | Go home (app → app switcher → home) |
| Long-press in left zone (< 15% from left) | Toggle search |
| Long-press in right zone (> 85%) | Toggle keyboard |
| Swipe left (in app) | **Back** — pop a subview, or background the app if at root |
| Swipe right (in app) | Cancel back / forward where applicable |

Back-swipe drives **predictive back**: `backProgress` rises with finger
travel; the foreground app shrinks proportionally toward 0.9. On
release past 50% threshold OR with velocity > 500 px/s, commit fires
`swipeBack` → `AppLifecycleManager.handleSystemBack()` → app-runner DBus
→ app's `MAppRouter.popRoute()` (subview pop) or falls through to
`closeApp()`.

**Edge zones.** The 15%/85% split is the system-wide gesture-zone
contract — apps must not steal touches in those columns. `MAppWindow`
clips them.

**Haptic coupling.** Every gesture threshold fires a haptic in the same
frame the spring starts. `MHaptics.light()` for taps, `medium()` for
gesture thresholds (short swipe up, search open), `heavy()` / `error()`
for destructive confirmations (power-menu reset, app-uninstall).
Springs and haptics fire together — never one without the other.

---

## 6. Materials & effects

### 6.1 `MGlass`

The chrome material. A `ShaderEffectSource` samples the live
framebuffer behind the surface, a `MultiEffect` runs a single-pass blur
+ tint, and the result is the lightly translucent panel the user sees
for the status bar, top bar, nav bar, dock, NowBar, QS shade, modals,
sheets, dropdowns.

Reads `MMotion.reduceBlur` and `MMotion.translucencyLevel` automatically.
Caller picks blur radius via `MBlur.blurFor(role)` — never an inline
number:

| Role | `MBlur.blurFor` | Use |
|---|---|---|
| `chrome` | 24 px | status bar, top bar, nav bar, dock, NowBar |
| `sheet` | 24 px | modal sheets, full-bleed sheets, QS shade |
| `dropdown` | 8 px | combo dropdowns, autocomplete popovers |
| `halo` | 8 px | focus halos / glows |
| `hairline` | 2 px | sub-1px glass tint on flat surfaces |

### 6.2 In-process compositor as material moat

This is the part competitors can't copy. Marathon's compositor + shell
+ every app surface live in one Qt scenegraph. That gives us, for free:

- **Sub-frame chrome+app coherence.** The status-bar reveal, nav-bar
  pill morph, and app-window scale can land in one composed frame.
  Wlroots-based stacks (phosh, gnome-shell-mobile) cannot — they're
  multi-process and pay one IPC round-trip per surface state change.
- **Live-surface textures in chrome.** The app's actual Wayland surface
  can be sampled by a `ShaderEffectSource` and displayed as a
  thumbnail, a glass-blurred backdrop, or a recents-card live preview —
  no separate snapshot capture. iOS does this; on Linux only Marathon
  currently can.
- **Zero-IPC scenegraph effects.** Drag-a-card-and-it-shrinks-the-app
  is one binding evaluation, not a `wl_surface.commit` round-trip.

These aren't future plans — they're the substrate the existing
predictive-back, vertical-minimize, and pop transitions already use.
Future work (live activities, glass-architecture lensing, recents
live-thumbs) compounds the advantage.

**Trade-off acknowledged.** A shell crash kills every app. Mitigation:
the cgroup v2 freezer + state-machine lifecycle (`AppLifecycleManager`)
+ `BeginBackgroundTask` model means apps survive shell restarts via
their separate processes. The compositor-split path is parked
(see `project_compositor_split_deferred` memory) — discipline beats
process boundaries here.

---

## 7. Chrome system

### 7.1 Status bar

Top 50 px (scaled). Glass material at `MBlur.blurFor("chrome")` with
`MColors.glassTitlebar` tint. Left cluster: battery + percent. Centre:
lock icon (lockscreen only) or `time`. Right cluster: signal · LTE ·
wifi · bluetooth.

The clock is *the* legibility test for the system — if it doesn't read
crisp on a teal-gradient lockscreen wallpaper, the type system is wrong.

### 7.2 Top bar (`MTopBar`)

Per-app chrome. Title in `XLarge` DemiBold; back chevron + optional
search icon at right. Background is glass for content-bleeding pages,
opaque `surface` for list-based pages (Settings, Notes). Apps pick by
declaring `topBarStyle: "glass" | "solid"` on `MPage`.

### 7.3 Tab bar (`MTabBar`)

Bottom-of-content tabs. Two visual treatments:

- **Underline** (default): a single 2 px teal-glow underline tracks
  between tabs via a shared-element `Behavior on x`. Cheaper to draw
  than chips, reads as iOS-native.
- **Pill** (opt-in): a `pill` radius capsule slides behind the active
  tab. Higher visual weight; reserved for primary nav (Mail folder
  picker, Calendar view switcher).

Both share the same animation token (`MMotion.stiffnessSpatialFor("tap")`).

### 7.4 Nav bar (`MarathonNavBar`)

System bottom strip. Pill centred at the bottom, 4 px tall (`xs`
spacing), `pill` radius. The strip is its own MouseArea — every system
gesture starts here. No tap action on the pill itself; it's a
*status affordance* (white when shell-active, dim when an app has
focus stolen, hidden in pin-screen mode).

### 7.5 Quick Settings shade

Pulled down from the top by the status bar's vertical gesture (or
swiped down on the nav-bar pill — that path is shared between QS dismiss
and minimize, disambiguated by start-Y). Two-stage shade: condensed
"split-shade" (brightness slider + 4 toggles) above 50% pull;
full-page chips + media controls below. Inspired by OneUI 7's
split-shade pattern — premium feel without the chrome cost of two
separate panels.

### 7.6 NowBar (planned)

A live-activity surface that promotes itself when the shell has an
active call, playing media, navigation in progress, or a running timer.
**One** canonical surface; features promote into it, they don't ship
their own widget. Visual contract: glass material, 40 px tall, primary
text + secondary metadata + dismiss/expand affordance. Mounts above
the nav bar, below the app content.

---

## 8. Components

### 8.1 Press feedback

The canonical recipe — every interactive surface in Marathon UI uses
it:

```qml
scale: pressed ? 0.96 : 1.0
Behavior on scale {
    SpringAnimation {
        spring: MMotion.springMedium      // or stiffnessSpatialFor("tap")
        damping: MMotion.dampingMedium
        epsilon: MMotion.epsilon
    }
}
onPressed: MHaptics.light()
```

**Press-scale convention:**

| Component | Scale on press |
|---|---|
| `MButton`, `MCircularIconButton`, `MImageButton`, `MCard`, `MActionBar`, `MTabBar` action | 0.96 |
| `MIconButton`, `MCheckbox`, `MRadioButton` | 0.92 |
| `MSlider` handle | 1.15 (grows on grab) |
| `MModal`, `MConfirmDialog`, `MSheet`, `MComboBox`/`MDropdown` menu | enter at 0.9-0.95, spring to 1.0 |

The earlier guidance "color-only, no scale, BB10-strict" is **deprecated**.
The BB10 aesthetic is preserved via sharp corners, dual-border depth,
the teal palette, and OLED-black surfaces — *not* by removing motion.
Material 3 Expressive's Google I/O 2025 reset confirmed: flat colour
states without spring are a 2018 pattern.

### 8.2 Ripple (`MRipple`)

Opt-in overlay. `MCard` uses it; buttons typically don't (scale + haptic
is sufficient and cheaper). Trigger from the touch point:

```qml
MRipple { id: ripple }
TapHandler { onTapped: (e) => ripple.trigger(Qt.point(e.position.x, e.position.y)) }
```

`MMotion.rippleDuration = slow (300 ms)`, `rippleMaxRadius 2.5x`,
`rippleOpacity 0.12`. Teal-tinted (`MColors.ripple`), never white.

### 8.3 Haptics (`MHaptics`)

Singleton in `MarathonUI.Effects`. `light/medium/heavy/selection/
success/error/warning/impact(intensity, duration)`. Forwards to a
`backend: QtObject` injected once by the shell at startup (the C++
`HapticManager` registered on `MarathonOS.Shell`). Reusable components
must go through `MHaptics`, not `HapticManager` directly — that keeps
`marathon-ui` decoupled from the shell module.

---

## 9. Accessibility & inclusivity

These are *primitives*, not features.

- **`MMotion.reduceMotion`** — bound from `org.gnome.desktop.interface
  enable-animations`. Every animation routes through `dur()`/`ease()`
  or `MMotion.roles` accessors.
- **`MMotion.reduceBlur`** + **`MMotion.translucencyLevel`** — bound
  from `org.gnome.desktop.a11y reduce-transparency`. `MGlass`
  collapses to opaque chrome when reduce-blur is on; otherwise scales
  blur+tint linearly by translucencyLevel.
- **Touch-target floor** — `MSpacing.touchTargetMin 45 px` (scaled).
  Even status-bar taps respect this — never less.
- **Typography scaling** — every type token multiplies by
  `Constants.scaleFactor`. The shell reads system DPI on init;
  on-device font-size override (planned) reads from
  `SettingsManager.fontScale`.
- **High-contrast accent path** — the teal `marathonTealBright`
  (`#1de9b6`) passes WCAG AAA against `bb10Black` for large text and
  AA for body. The dim teals are for non-text decoration only.
- **Screen reader** — `Accessible.name`/`role`/`description` on every
  primitive in `MarathonUI.Core` and `Containers`. Apps inherit by
  using the primitives; no custom QML draw paths should be reachable
  by AT.

---

## 10. Performance contract

The L5's etnaviv GLES2 is the floor; if it runs there at 60 fps it
runs anywhere. These are the rules the rendering pipeline depends on:

1. **Opaque first.** All fills are fully opaque except for modal
   overlays (`MColors.overlay` 85%), glass chrome (72-85%), ripple
   (12%), accent tints. Don't introduce new 90-95% alpha "for the
   look".
2. **No `layer.enabled`** except for SVG colourisation in `Icon.qml`.
   No `FastBlur` / `GaussianBlur` anywhere. `MultiEffect` permitted
   only on transient popups (§3).
3. **No `clip: true` unless overflow is real.** Stencil ops are
   expensive on Mali/Broadcom/etnaviv.
4. **No infinite animations on hidden items.** Gate `running` on
   visibility OR via `MMotion.gate(cond)`. CODING_RULES C8.
5. **Springs on `scale`/`opacity` only**, not on `width`/`height`
   (triggers layout recalculation).
6. **ListView delegates use `cacheBuffer` and `reuseItems`.** Anything
   longer than ~20 items is a delegate-recycling view, not a Column/Row.
7. **`MARATHON_LAYER_SAMPLES`** — every `layer.samples` value gates on
   this env (default 4, override 0 on GPUs without HW MSAA). The L5
   ships with override 0. See the Etnaviv MSAA trap memory.
8. **Tokens, never inline hex.** CODING_RULES C12.

**Targets:** 60 fps on the L5 (etnaviv GC7000Lite) and Pi 5;
< 100 ms gesture response (finger-down → first frame);
< 500 ms QML app launch; < 1 s native app launch;
< 100 MB RSS for the shell process at rest.

---

## 11. Adoption rules

### When adding a new component

1. Belongs in `marathon-ui/` if reusable across apps + shell; in
   `shell/qml/components/` if shell-only.
2. Every color: `MColors`. Every spacing: `MSpacing`. Every radius:
   `MRadius`. Every duration/spring: `MMotion.durationFor(role)` /
   `MMotion.stiffnessSpatialFor(role)`. No inline values.
3. Press feedback uses the canonical recipe (§8.1). Haptic + spring
   fire together.
4. If it has depth: dual-border (§3). If it's a transient popup:
   `MultiEffect` allowed. Otherwise neither.
5. Accessibility props (`Accessible.name`/`role`/`description`)
   declared, not omitted.
6. Lint clean, no `qmllint` warnings.

### When bumping a token

1. Identify the role being changed (a spring stiffness, a colour, a
   duration). If it's not in a role table, propose a new role first.
2. Update the role/token in `marathon-ui/Theme/*.qml`.
3. Update **this doc**. The doc is the change log for the system.
4. Sweep the codebase for inline duplicates of the old value
   (`rg '#1de9b6' --type qml`) and migrate or leave a comment
   explaining the exception.

### Audit cadence

Every ~50 commits or before a release, run a full audit:

- `docs/ux-audit-rNNN.md` — drop the rev tag, summarise what regressed,
  what improved, what's still on the backlog.
- Visual regression: snap the canonical screens (lockscreen, home,
  Settings root, Settings/WiFi, Calendar week, Mail inbox, Camera
  viewfinder) and diff against the previous rev's snaps.
- Performance: 60 fps swept on L5 + Pi 5; PSI Critical never sustained.

---

## 12. Power model — Marathon-Doze

Marathon does NOT use S3 suspend for the daily power-key / idle-timer
flow. It uses **Marathon-Doze**: kernel stays running, display + GPU
power-gated, background apps frozen via the cgroup v2 freezer, wifi
in chip-level PSM (radio idles but association stays alive). Wake from
Doze is sub-100 ms — no kernel resume penalty, no wifi/modem reattach,
push connections survive. This is iOS Always-On / Android Doze in
architecture; the daily user experience is "the screen turns off and
back on, and everything is exactly where it was".

### State machine

| State | Visible | CPU | Display | Wifi/modem | Background apps |
|---|---|---|---|---|---|
| ACTIVE | yes | full | on | full power | per-app freezer policy |
| DOZE | screen off | cpuidle WFI | KMS off, backlight 0 | PSM on, associated | frozen via cgroup |
| SUSPEND (S3) | screen off | off | off | torn down | killed/lost |
| OFF | — | — | — | — | — |

Transitions:

| From → To | Trigger |
|---|---|
| ACTIVE → DOZE | Power-key short press; idle-timer expiry (3 min default) |
| DOZE → ACTIVE | Power-key short press; modem ring/SMS; incoming network packet (when WoWLAN supported) |
| ACTIVE → SUSPEND | PowerMenu → "Deep Sleep" (explicit); critical-battery handler |
| SUSPEND → ACTIVE | Power-key; rtcwake scheduled wake |
| any → OFF | PowerMenu → "Power Off"; PowerMenu long-press |

### Trade

iOS-class always-reachable standby costs roughly 5-10× the idle draw
of true S3. On L5's 4500 mAh battery that's ~3-5 days standby vs ~20
days for S3 — still vastly better than screen-on, and the price of
"push notifications actually work". Critical-battery + explicit
"Deep Sleep" preserve the S3 path for the cases where battery beats
reachability.

### Code surface

- `PowerPolicyController::enterDoze()` / `exitDoze()` — bundles the
  policy (display off → freeze debounce 0 → wifi PSM on, and the
  mirror on exit). `dozing` property visible from QML.
- `PowerPolicyController::sleep()` — backwards-compat alias that now
  routes to `enterDoze()` (was `m_powerManager->suspend()` historically).
- `PowerPolicyController::deepSleep()` — the new explicit S3 path,
  reserved for PowerMenu "Deep Sleep" + critical-battery.
- `PowerBatteryHandlerCpp::turnScreenOff/On` — power-key entry point;
  routes through `enterDoze` / `exitDoze` when PowerPolicy is wired.
- `DisplayPolicyController::forceScreenOn` — r293; re-syncs `m_screenOn`
  + emits `screenOnChanged` so QML hooks (dimState, idle timer) fire
  on the resume edge.
- `DisplayManagerCpp::setScreenState(true)` — r293; re-writes
  `brightness` after `bl_power=0` to defeat the i.MX 8M PWM glitch.
- `main.cpp` — wires `PowerManagerCpp::resumedFromSuspend` to BOTH
  `forceScreenOn` (backlight) AND `exitDoze` (state cleanup if S3 was
  triggered out-of-band).

### Open questions (measured, not assumed)

- Does i.MX 8M Quad cpuidle actually power-gate cores in WFI on
  this kernel, or does it spin? Only `WFI` (1 µs) and `cpu-sleep`
  (1500 µs) are exposed; no cluster-off state. Real power impact of
  Doze vs S3 is TBD until clean fuel-gauge measurements land.
- Modem behaviour in long-Doze windows — the BM818-E1 udev rule
  keeps it reachable for calls/SMS, but `qmi_wwan` kernel driver
  prevents USB autosuspend from actually engaging (measured 89.7%
  active even with ModemManager stopped). Kernel-level fix needed.

### Governor choice (2026-07-01)

Marathon ships **ondemand**, not schedutil. Under schedutil on
imx8mq's coupled A53 cluster, any SCHED_FIFO task wake boosts the
whole cluster to 1.5 GHz. The L5 has ~25 threaded IRQ handlers at
`SCHED_FIFO prio 50` (PMIC, RTC, fuel gauge, touch, wifi/mmc SDIO,
GPU, migration). At ~1000 IRQs/s the cluster is boosted to max 58.8%
of active time under schedutil.

Ondemand samples load every 100 ms without the RT-boost path. Live
measurement: 1.5 GHz residency 58.8% → 11.7%, 100 MHz residency
29.8% → 73.5%. Doze enter/wake timing unchanged (~300 ms). Ping in
Doze with PSM on: 10/10, 14-39 ms RTT.

Applied at boot via `marathon-cpu-governor.service` (packaging repo).
If ondemand ever causes touch-to-frame latency issues, either revert
to schedutil or patch the kernel to skip RT-boost for non-DL tasks.

The architecture is committed; the tuning constants (idle-timer
duration, PSM aggressiveness, optional foreground-app freezing at
deep-Doze depth) iterate from the deployed baseline.

## 13. Open tabs (post-baseline backlog)

What's known-missing as of this baseline. Each is a sub-doc / spike,
not a vague aspiration:

- **NowBar / Live Activities** — single promotion surface for
  call/media/nav/timer (§7.6). Needs a NotificationModel-side
  "ongoing + progress" field and a shell-side mount slot above the
  nav-bar.
- **Glass-architecture lensing** — let `MGlass` sample not just the
  flat backdrop but a refracted lens view (iOS 26 Liquid Glass
  pattern). Shader work; gates on `MMotion.reduceBlur`.
- **Live recents thumbnails** — task switcher cards show a live
  framebuffer of the running app (in-process compositor moat).
- **Predictive-forward** — the opposite of predictive-back; a
  next-page hint as the user starts a forward gesture (rare, but
  iOS-grade polish).
- **Variable font animation** — Slate is variable; animate weight on
  hover/focus for hero numerals (clock, percentages, timers).
- **Per-app accent override** — apps declare an accent in their
  manifest; `MColors.accent` is alias-resolved per-app context, with
  the marathonTeal as fallback.
- **Spring-coupled chrome morph** — status bar height bound to scroll
  position via the same spring as the page transition; chrome and
  content move as one.

---

## Status & ownership

- **Target hardware**: Librem 5 (i.MX 8M Quad + etnaviv GC7000Lite,
  720×1440), Raspberry Pi 5 (Cortex-A76 + V3D, varies), pmOS QEMU
  developer simulator.
- **Source of truth**: `marathon-ui/Theme/*.qml`. This doc reflects
  those files; when they diverge, update this doc.
- **Cross-references**: `docs/CODING_RULES.md` for the surrounding
  engineering rules (C8 lifecycle, C11 no-context-properties, C12
  no-inline-values). `docs/ARCHITECTURE.md` for the shell process
  model + in-process compositor rationale. `docs/MAPP_GUIDE.md` for
  how apps consume the design system.
