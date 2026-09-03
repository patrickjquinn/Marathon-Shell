# Marathon OS — Redesign Handoff Analysis

Analysis of the `MarathonOS-handoff` design bundle(s) (extracted to `docs/redesign/marathonos/`). No code has been changed; this is a prep document for the redesign work on the `ux-overhaul` branch.

Source files referenced are relative to `docs/redesign/marathonos/project/`.

## 0. Bundle version

Two bundles have been shared:

- **v1** (`MarathonOS-handoff.zip`) — initial drop; README pointed at `design-system/Marathon Design System.html`.
- **v2** (`MarathonOS-handoff (1).zip`) — canonical; README now points at **`Marathon OS.html`** (the design canvas — master inventory of every screen). Adds one wallpaper-reference screenshot. **Every other file is byte-identical to v1.**

The v2 README's reframing is the key signal: the canvas page (`Marathon OS.html`) is the authoritative entry point. The design-system page (`design-system/Marathon Design System.html`) is the reference; the canvas is the spec.

## 1. Headline finding — this is an evolution, not a clean break

Every load-bearing token in the new system is **identical** to what's already in `marathon-ui/Theme/`:

| Token family | New design | Current code | Same? |
|---|---|---|---|
| Surface ramp (`elev-0…5`) | `#040404 / #0a0a0b / #121213 / #1c1c1d / #282829 / #353536` | `MElevation.getSurface(0..5)` | ✅ identical |
| Teal accent (5 stops) | `#006B5D / #00897B / #00BFA5 / #1DE9B6 / #5DFFDC` | `MColors.marathonTeal*` | ✅ identical |
| Spacing | `5 / 10 / 16 / 20 / 32 / 40` | `MSpacing.xs…xxl` | ✅ identical |
| Touch targets | `45 / 60 / 70 / 90` | `MSpacing.touchTarget*` | ✅ identical |
| Radius | `0 / 2 / 4 / 6 / 8 / 999` | `MRadius.none…full` | ✅ identical |
| Motion durations | `80 / 160 / 240` ms | `MMotion.micro / quick / moderate` | ✅ identical |
| Easing curves | std `(.2,0,.2,1)`, dec `(0,0,.2,1)`, acc `(.4,0,1,1)`, spring `(.34,1.56,.64,1)` | `MMotion.easing*Curve` | ✅ identical |
| Text ladder | primary `#F5F5F5` / secondary `#6A6A6A` / tertiary `#4A4A4A` / hint `#2A2A2A` | `MColors.textPrimary…textHint` | ✅ identical |
| Glass tints | `glass-titlebar 0.72 / tabbar 0.78 / actionbar 0.82 / header 0.85` | `MColors.glass*` | ✅ identical |

This means the redesign's surface treatment, motion feel, and density grid can sit on the existing token foundation. Every QML file in the shell already references these values; **none of those references need to change**.

The new design adds capabilities on top:

- New tokens that didn't exist before
- A different type system (font + scale)
- New component primitives (NowBar, ActiveFrame, MarathonMark, GlassBg)
- New shell surfaces (Active Frames home, Marathon Intelligence, Spotlight, Wallet, Privacy Dashboard, Focus Modes, Now Bar)
- A different organisational structure (one `Theme` singleton vs six)
- A different module URI (`dev.marathon.UI 1.0` vs `MarathonUI.Theme/Core/...`)

## 2. Token deltas — what's new

### 2.1 Type system — the biggest token change

**Font:** `Sora` (variable, 100–800) replaces `Slate`. Qt 6.7+ picks weight from one variable file. JetBrains Mono stays.

**Type scale:** rebuilt around iOS-aligned roles, not abstract sizes:

| Role | px | weight | tracking | Used for |
|---|---|---|---|---|
| Display | 96 | 200 | -3 | Lock-screen clock, calculator readout |
| Title L | 48 | 200 | -1.2 | Hub, large-title hero pages |
| Title 1 | 34 | 200 | -0.8 | App top bars (Settings, Mail) |
| Title 2 | 28 | 300 | -0.5 | Music now-playing track |
| Title 3 | 22 | 500 | -0.3 | Section heroes, modal titles |
| Headline | 17 | 600 | -0.1 | List row primary text |
| Body | 17 | 400 | 0 | Default reading |
| Callout | 16 | 400 | 0 | Modal body, prompts |
| Subhead | 15 | 500 | -0.1 | Form labels |
| Footnote | 13 | 400 | 0.1 | Inline metadata |
| Caption | 12 | 500 | 0.2 | Date headers, eyebrows |
| Eyebrow | 11 | 700 | 1.4 | UPPERCASE section banners |
| Mono | 13 | 500 | 0.2 | Numerics, code, terminal |

`MTypography` currently exposes `sizeXSmall (12) / Small (14) / Body (16) / Large (18) / XLarge (24) / XXLarge (32) / Display (40) / Huge (48) / Gigantic (96)` — these are abstract sizes, not semantic roles. The new scale needs:

- Tabular numerics enabled on numeric Text via `font.features: { "tnum": 1 }` (Qt 6.7+).
- Variable weight axis: `font.weight: 200 / 400 / 500 / 600 / 700` from one file.
- Letter-spacing per role (tight negative on display sizes, positive on eyebrow).

### 2.2 New colour tokens

- **`--teal-gradient`** — `linear-gradient(180deg, #1de9b6 0%, #00bfa5 50%, #00897b 100%)`. Used on primary button background, active tab indicator bar.
- **Secondary muted palette** — only for **semantic** colour, never decoration:
  - `--sec-blue   #3A6B9C` — Maps water, "Sleep" focus, message identity
  - `--sec-green  #4A8A5E` — Maps parks, "Move" ring, signal-good
  - `--sec-amber  #C89545` — Camera permission, "use caution"
  - `--sec-rose   #A85968` — Mic permission, Activity stand ring, Health heart
  - `--sec-violet #6B5D8F` — Mentions, Linear, categorical chip
  - Saturation held ~40 so they sit calmly beside teal.
- **`--teal-halo`** — `rgba(0,191,165,0.18)` — used in focus rings and accent glows.

### 2.3 New radius

- **Squircle 14** — app icons only. 64×64 dp app tile, 14 dp radius. Not used anywhere else. Everywhere else stays sharp (md 4 default).

### 2.4 Reduce-motion plumbing

The design system specifies a `Theme.motion.dur(token)` / `Theme.motion.ease(token)` helper that returns `micro` duration and `OutQuad` easing when `Theme.reduceMotion` is true. Bound at startup from:
- `gsettings get org.gnome.desktop.interface enable-animations` (GNOME Mobile)
- `kdeglobals.KAccessibilityCommon.skipFancyEffects` (Plasma Mobile)

Currently absent.

## 3. Theme structure — the architectural choice

The design doc (`ds-engineering.jsx:90–217`) specifies **one** `Theme.qml` singleton with **nested QtObject groups**:

```qml
pragma Singleton
QtObject {
    readonly property color tealBright: "#1DE9B6"
    readonly property QtObject spacing: QtObject { readonly property int md: 16 ... }
    readonly property QtObject touch:   QtObject { readonly property int min: 45 ... }
    readonly property QtObject radius:  QtObject { readonly property int md: 4 ... }
    readonly property QtObject type:    QtObject { readonly property string ui: "Sora" ... }
    readonly property QtObject duration: QtObject { readonly property int quick: 160 ... }
    readonly property QtObject easing:  QtObject { readonly property int spring: Easing.OutBack ... }
    readonly property QtObject glass:   QtObject { readonly property real chromeBlur: 14 ... }
}
```

Consumer call sites become `Theme.tealBright`, `Theme.spacing.md`, `Theme.type.body`, etc.

**Current code:** six singletons — `MColors`, `MElevation`, `MMotion`, `MSpacing`, `MRadius`, `MTypography` — referenced as `MColors.teal`, `MSpacing.md`, etc.

You answered: migrate to one Theme singleton with nested QtObjects.

**Scope:** every QML file in the shell + apps that references `MColors.X` / `MMotion.X` / etc. — roughly 100+ files. Mechanical rename. Per CODING_RULES G5 this is one cross-cutting commit; the subject must say so. Recommended to do **last** of the foundation work, after tokens are settled, so we don't rename twice.

## 4. Module URI

Design says `import dev.marathon.UI 1.0`. Current is `import MarathonUI.Theme / MarathonUI.Core / MarathonUI.Containers / MarathonUI.Controls / MarathonUI.Effects / MarathonUI.Feedback / MarathonUI.Lists / MarathonUI.Modals / MarathonUI.Navigation`.

The current split is by *category* (Containers vs Controls vs Effects); the design specifies a **flat catalog** under one URI. Migrating means:

- Collapsing 8 sub-modules into one.
- All marathon-ui consumers (every app + every shell QML) need their import lines updated.

This is the biggest cross-cutting rename in the migration. Same comment as Theme structure: do it once, do it late.

## 5. New components required

Specs are in `ds-components.jsx` and `ds-engineering.jsx`. The full catalog from the design (`ds-engineering.jsx:61–84`):

```
MButton, MCard, MRow, MToggle, MSlider, MChip, MAvatar,
MStatusBar, MTopBar, MTabBar, MDock, MNowBar, MActiveFrame,
MDialog, MHUD, MSearchField, MIcon, MMarathonMark,
effects/GlassBg, effects/TealGlow
```

Mapped to existing components and gaps:

| Design name | Maps to | Status |
|---|---|---|
| MButton | `marathon-ui/Core/MButton.qml` | Exists, needs primary teal-gradient variant + spec match |
| MCard | `marathon-ui/Containers/MCard.qml` | Exists, may need double-edge stroke tweak |
| MRow | `marathon-ui/Containers/MListItem.qml` | Exists, may need 60px min + new typography |
| MToggle | `marathon-ui/Controls/MToggle.qml` | Exists, may need 44×26 sizing + teal-halo glow exact |
| MSlider | `marathon-ui/Controls/MSlider.qml` | Exists, may need 4px track + teal-gradient fill |
| MChip | None directly | **New** — pill chip, filter chip variant |
| MAvatar | None | **New** — 44×44 circle, monogram + tint |
| MStatusBar | `shell/qml/components/MarathonStatusBar.qml` | Exists, needs glass refactor |
| MTopBar | `marathon-ui/Navigation/MTopBar.qml` | Exists, **needs full rebuild** for 96px large-title with glass |
| MTabBar | `marathon-ui/Navigation/MTabBar.qml` | Exists, may need teal-gradient indicator + glow |
| MDock | `shell/qml/components/MarathonNavBar.qml` (closest) | **New** — 64px home-gesture row, phone+camera+page-dots |
| MNowBar | None | **New** — 36px live-activity strip (music/call/timer/nav) |
| MActiveFrame | None | **New** — BB10-style live tile (snapshot + 1Hz live region) |
| MDialog | `marathon-ui/Modals/MConfirmDialog.qml` (closest) | Exists, may need permission-dialog variant |
| MHUD | None directly | **New** — system overlay (volume / brightness HUD) |
| MSearchField | None | **New** — Spotlight prefix with Marathon mark + mic |
| MIcon | `marathon-ui/Core/Icon.qml` (Lucide) | Exists, **needs new font** — design specifies Phosphor Light, NOT Lucide |
| MMarathonMark | None | **New** — three concentric horizon arcs in `QtQuick.Shapes` |
| GlassBg | None | **New** — backdrop blur wrapper (MultiEffect) |
| TealGlow | None | **New** — directional accent halo |

**Iconography change:** design uses **Phosphor Light** (1px stroke, round caps, viewBox 24); current uses Lucide. Switching means vendoring Phosphor SVGs (or font), changing `Icon.qml` to load from the new pack, and re-checking every `iconName:` reference. ~150 icon references in the shell.

## 6. App icons

The design defines **21 bespoke app icons** (`app-icons.jsx`), each a 64×64 squircle (14 px radius) with a specific gradient and glyph:

`IconPhone IconMessages IconMail IconBrowser IconStore IconCalc IconCamera IconMusic IconCalendar IconClock IconSettings IconMaps IconGallery IconNotes IconContacts IconFiles IconMI IconWallet IconHealth IconWeather IconVoice`

Each has documented colours and geometry. Construction pattern:

- `AppIconFrame` — 64×64, radius 14, shadow `0 0 0 1px rgba(0,0,0,0.6)` + `inset 0 1px 0 rgba(255,255,255,0.15)` + `0 8px 16px -8px rgba(0,0,0,0.7)`
- Background: per-app gradient (mostly slate/black or teal)
- Glyph: SVG at 55–90% of frame, white or teal
- Optional inner texture (vinyl grooves, grid buttons, dots, lines)

Marathon currently has `marathon-ui/Core/MAppIcon.qml` which is a generic LunaSVG/Icon wrapper — would need to be re-purposed as the squircle frame, with per-app icon components rendered inside as the subject.

## 7. Wallpapers — thirteen, not three

Full specs in `wallpapers.jsx`. The canvas (`Marathon OS.html:238–252`) ships **thirteen** named wallpapers, all 390 × 844 SVG, palette-locked to teal + neutrals. Every wallpaper layers a shared `Horizon` primitive at `y = 540` (golden ratio of 844) — that single horizontal line is the family's anchor.

| # | Function | Canvas label | Composition |
|---|---|---|---|
| 39 | `WallpaperSlateAurora` | **Slate Aurora** *(default)* | Aurora ribbon sweeping bottom-left → top-right, 5 topographic curves, bottom-left teal halo, 2 diagonal accent lines, 9 light particle dots |
| 40 | `WallpaperLongRun` | **Long Run** | 5 concentric horizon arcs in teal ramp (radii 90/150/210/280/360, opacity 0.30→0.85, colour `#006b5d → #5dffdc`), radial glow centred at horizon, sun dot |
| 41 | `WallpaperFlowfield` | **Track** | 7 parallel running lanes (`Δy = -90…+90, step 30`), centre lane brightest (op 0.55), edges fade (op 0.17). Track-style perspective fade on left/right edges. Radial teal glow at horizon |
| 42 | `WallpaperMesh` | **Mesh** | Engineering blueprint grid: 6px fine grid (opacity 0.022), 30px main grid (teal opacity 0.07). One bright crosshair on horizon, 3px teal node + halo, radial vignette |
| 43 | `WallpaperTopographic` | **Contour** | 12 concentric ellipses centred on horizon (`rx = 38+i*28`, `ry = rx*0.62`, opacity 0.55→0.11), inner ellipse highlighted. Radial glow, horizon, sun dot |
| 44 | `WallpaperDrift` | **Stride** | 22 rows × 5 columns of diagonal hairline strokes (angle 60°, lengths 22–34px), opacity peaks at horizon (0.50) and fades to edges (0.20). Radial teal glow offset right |
| 45 | `WallpaperStriae` | **Striae** | 140 horizontal lines (density curve peaks at horizon, opacity 0.04–0.30, stroke 0.3–0.8). Centre band glow. Strong horizon anchor at opacity 0.85 |
| 46 | `WallpaperHalftone` | **Halftone** | Radial dot density centred at horizon: 18 cols × 38 rows offset, radius `3.0*(1-t)` and opacity `0.6*(1-t)` where `t = distance/460` |
| 47 | `WallpaperPulse` | **Pulse** | 8 radar rings centred at horizon (radii 40 / 90 / 150 / 220 / 300 / 400 / 520 / 680), innermost thickest, opacity 0.55→0.13. Radial teal glow + sun |
| 48 | `WallpaperTwilight` | **Dawn** | Sunrise vertical gradient (`#1f2840 → #3a4055 → #5a4a4a → #040404` across 0/30/50/horizon), radial sun glow at horizon, **one** offset morning star (`cx=285, cy=160`) |
| 49 | `WallpaperTundra` | **Tundra** | Cool sky vertical gradient (`#3a6b9c 0.55 → #1f3a5c 0.45 → #040404 at horizon`), centre-glow at horizon, 2 concentric arcs above horizon (radii 140 / 220), sun dot |
| 50 | `WallpaperCarbon` | **Carbon** | Pure near-black + one diagonal accent line (`x1=0,y1=700 → x2=390,y2=200`, teal 0.08 opacity). The "calm" wallpaper for settings-heavy screens |
| 51 | `WallpaperIndigoDusk` | **Indigo Dusk** | Radial gradient at `cx=0.5, cy=0.4` (`#1de9b6 0.35 → #3b3bb0 0.25 → #040404`). 30 scattered white star dots (seeded deterministic), no horizon |

Shared primitives:

- **`const HORIZON_Y = 540`** — golden-ratio horizon anchor, exported to every wallpaper.
- **`<Horizon opacity sun />`** — single horizontal line at `y = HORIZON_Y` (teal `#1de9b6` 0.7 width + bright echo `#5dffdc` 0.3 width). `sun` adds a centred 2.5 r dot + 8 r halo. Used by 10 of 13 wallpapers — Carbon and IndigoDusk skip it intentionally (Carbon is minimal; Indigo Dusk centres on its own radial focal point).
- All are static SVG, no animation, no `live: true` cost.

**For QML implementation:** each wallpaper is straightforward `QtQuick.Shapes` + `Rectangle` gradients. The `Horizon` primitive becomes a reusable QML `Item` (~15 lines). Total asset code is moderate — most complexity is in the gradient definitions which translate directly to `LinearGradient`/`RadialGradient` declarative form.

Per-app surfaces in screens reference these by import name, e.g. `<WallpaperSlateAurora/>` on the lock screen. There is no "wallpaper-of-the-day" or schedule — the user picks one in Settings.

## 7a. Canvas inventory — `Marathon OS.html` (52 numbered artboards)

The canvas is the spec. Every artboard is 390 × 844, wrapped in a sharp-cornered `Phone` device frame (`borderRadius: 0`, 1px border `#1a1a1a`, drop shadow). The order matters — it's the order the project owner expects screens to land in.

| # | Section | Surface | Source |
|---|---|---|---|
| **Shell — system surfaces** | | | |
| 00 | Shell | Design System reference card *(links to ds docs)* | `Marathon OS.html:70` |
| 00 | Shell | `BootSplash` — teal disc + M, loading bar | `screens-shell.jsx:11` |
| 01 | Shell | `LockScreen` — clean (clock + date + 3 notifications + swipe hint) | `screens-shell.jsx:51` |
| 02 | Shell | `LockNowBar` — lock with active call in Now Bar | `screens-modern.jsx:698` |
| 03 | Shell | `LockMedia` — lock with music widget | `screens-shell.jsx:165` |
| 04 | Shell | `ActiveFramesHome` — Now Bar + 2×2 live tile grid + pinned dock | `screens-modern.jsx:12` |
| 05 | Shell | `HomePage1` — 4×4 app icon grid (legacy view) | `screens-shell.jsx:369` |
| 06 | Shell | `AppDrawer` — A-Z list with search | `screens-shell.jsx:391` |
| 07 | Shell | `TaskSwitcher` — 2×2 card grid of running apps | `screens-shell.jsx:469` |
| 08 | Shell | `QuickSettings` — tile grid + sliders + music strip | `screens-shell.jsx:613` |
| 09 | Shell | `HubScreen` — unified inbox (search + chips + monogram rows) | `screens-shell.jsx:859` |
| 10 | Shell | `Spotlight` — AI-native search with citations | `screens-modern.jsx:793` |
| **Marathon Intelligence** | | | |
| 11 | MI | `MarathonIntelligence` — assistant w/ suggestions + conversation | `screens-modern.jsx:259` |
| 12 | MI | `WalletApp` — passkeys + payment cards | `screens-modern.jsx:410` |
| 13 | MI | `FocusModes` — DnD / Grayscale / Sleep profile grouping | `screens-modern.jsx:500` |
| 14 | MI | `PrivacyDashboard` — privacy score ring + permission access log | `screens-modern.jsx:563` |
| **System Overlays** | | | |
| 15 | Overlay | `PermissionDialog` — modal w/ app icon + permission | `screens-shell.jsx:1028` |
| 16 | Overlay | `IncomingCall` — caller monogram + quick replies + accept/decline | `screens-shell.jsx:1083` |
| 17 | Overlay | `SystemHUD` — floating glass bar (volume scrubbing) | `screens-shell.jsx:1312` |
| 18 | Overlay | `KeyboardActive` — QWERTY + prediction + teal send button | `screens-shell.jsx:1178` |
| **OOBE — first-run flow** | | | |
| 19 | OOBE | `OOBELanguage` — language/region picker (step 1) | `screens-apps-2.jsx:850` |
| 20 | OOBE | `OOBEWifi` — Wi-Fi network list (step 2) | `screens-apps-2.jsx:909` |
| 21 | OOBE | `OOBEPasskey` — biometric enrollment w/ pulse rings (step 3) | `screens-modern.jsx:618` |
| 22 | OOBE | `OOBEFinish` — success checkmark "You're all set" | `screens-apps-2.jsx:978` |
| **Settings** | | | |
| 23 | Settings | `SettingsApp` — profile + sections | `screens-apps-1.jsx:25` |
| 24 | Settings | `SettingsDisplay` — brightness + scale + accent | `screens-apps-1.jsx:81` |
| **Communication** | | | |
| 25 | Comm | `PhoneDialer` — large number display + 3×4 keypad | `screens-apps-1.jsx:171` |
| 26 | Comm | `MessagesList` — threads with monogram + unread badge | `screens-apps-1.jsx:234` |
| 27 | Comm | `MessagesThread` — bubbles + typing + composer | `screens-apps-1.jsx:295` |
| 28 | Comm | `MailInbox` — left teal stripe on unread | `screens-apps-1.jsx:391` |
| **Web & Store** | | | |
| 29 | Discover | `BrowserApp` — glass URL bar + bottom toolbar | `screens-apps-1.jsx:450` |
| 30 | Discover | `StoreDiscover` — featured hero + trending rail + updates | `screens-apps-1.jsx:554` |
| **Media & Capture** | | | |
| 31 | Media | `MusicNowPlaying` — album art + scrubber + device strip | `screens-apps-2.jsx:9` |
| 32 | Media | `CameraApp` — viewfinder + grid + reticle + mode tabs | `screens-apps-2.jsx:139` |
| 33 | Media | `GalleryApp` — 3-col grid + moment sections + memory tile | `screens-apps-2.jsx:718` |
| **Utilities** | | | |
| 34 | Utils | `CalendarApp` — month grid + today highlight + event bars | `screens-apps-2.jsx:253` |
| 35 | Utils | `ClockApp` — analog dial + world clocks | `screens-apps-2.jsx:634` |
| 36 | Utils | `CalculatorApp` — display + operator chips + 5×4 keypad | `screens-apps-2.jsx:363` |
| 37 | Utils | `MapsApp` — SVG roads + pin + bottom info card + actions | `screens-apps-2.jsx:472` |
| 38 | Utils | `NotesApp` — pinned card + folder tabs + hashtags | `screens-apps-2.jsx:793` |
| **Wallpapers** (39–51) | | | see §7 |

**Sections expose the natural commit/staging order** if you want to slice work by area: ship Shell → Intelligence → Overlays → OOBE → Settings → Communication → Discover → Media → Utilities → Wallpapers.

## 8. New shell surfaces — what doesn't exist today

These are entirely new and need both QML implementation AND new C++/data plumbing:

| Surface | What it is | Backend gap |
|---|---|---|
| **Now Bar** | 36 px live-activity strip on home + lock. Variants: music / call / nav / timer / pulse | Needs a `LiveActivityManager` aggregating MPRIS + Telephony + Navigation + Alarms into one ranked feed. Significant. |
| **Active Frames home** | BB10-style live tile grid replacing pages of static icons. Tile = snapshot + 1 Hz live region | Needs per-app snapshot lifecycle + 1 Hz update channel. Major. |
| **Marathon Intelligence (MI)** | On-device AI surface with conversational UI, suggestion cards, inline citations | No backend exists. Either skip / stub for now or stage with a placeholder. |
| **Spotlight** | AI-native search returning MI answer + top hit + sources | Wraps existing `UnifiedSearchServiceCpp` + MI. |
| **Wallet** | Passkeys + payment cards | No backend; would need fprintd / TPM / WebAuthn integration. Multi-week. |
| **Privacy Dashboard** | Privacy score ring + 24-h permission access log | Leverages `MarathonPermissionManager`; needs an access-log persistence layer. |
| **Focus Modes** | Grouping DnD / Grayscale / Hub mute / Alarms-only into profiles | Wraps `SettingsManager` + a new state machine. Modest. |
| **Hub redesign** | Unified inbox — search, account chips, monogram rows | Backend mostly exists (`NotificationModel`, contacts, mail/SMS via apps). |
| **Quick Settings redesign** | Cleaner tile grid, page dots + bar | Pure QML refactor. |

## 9. Screens being redesigned

Inventory from `screens-shell.jsx` + `screens-apps-1/2.jsx` + `screens-modern.jsx`:

**Shell surfaces:** BootSplash, LockScreen (clean), LockMedia (with music), LockNowBar, HomePage1 (4×4 grid), AppDrawer, TaskSwitcher (2×2 cards), QuickSettings, HubScreen, PermissionDialog, IncomingCall, KeyboardActive, SystemHUD, ActiveFramesHome.

**Apps fully redesigned (14):** Settings (+ SettingsDisplay sub-page), Phone (Dialer), Messages (List + Thread), Mail (Inbox), Browser, Store (Discover), Music (Now Playing), Camera, Calendar, Calculator, Maps, Clock, Gallery, Notes.

**Modern surfaces:** Active Frames home, Now Bar (variants), Marathon Intelligence, Wallet, Focus Modes, Privacy Dashboard, OOBE Passkey, Spotlight.

**OOBE flow:** Language → WiFi → Passkey → Finish.

## 10. Engineering constraints from the design

From `ds-engineering.jsx:39–58`:

- **Qt 6.7 LTS minimum, 6.8+ recommended** — current `CMakeLists.txt` declares `Qt6 6.4...6.12`. The minimum needs bumping (or guards for the features below).
- **`font.features` for tabular numerics** — Qt 6.7+ only. Used on every clock, percentage, currency, duration.
- **Variable font axes** — Qt 6.7+ — for Sora's single-file 200–700 weight range.
- **`MultiEffect`** — Qt 6.5+, already available, used everywhere for glass.
- **`enum` in QML** — Qt 5.14+, used for MButton.Variant etc.
- **RHI Vulkan on Linux/Wayland** — `QSG_RHI_BACKEND=vulkan` recommended.
- **Target hardware:** PostmarketOS / Linux Mobile (PinePhone Pro, OnePlus 6). Existing rules for Pi 4 / HackBerry still apply.

The Qt 6.4 minimum currently in `CMakeLists.txt` is from Droidian compatibility. Bumping to 6.7 needs confirmation that Droidian's Qt has moved on.

## 11. Performance rules carried over

`ds-engineering.jsx:582–622`:

- Status bar: single QML, cached at window root, never re-instantiated.
- List rows: `ListView + delegate` only, never `Repeater` above 20 items.
- Now Bar: model is a shared singleton.
- Wallpaper: SVG drawn into `ShaderEffectSource` once, never animated.
- Glass blur: `live: true` OK on GPU, cap blur at 20.
- Active Frames: snapshot to `ShaderEffectSource` at suspend; max ~8 live before eviction.

All consistent with existing CODING_RULES.md C8/C9 and current shell performance posture.

## 12. Voice & tone, accessibility

`ds-components.jsx:441–522`:

- Sentence case for buttons/titles: "Set up Touch ID", "Get started".
- UPPER CASE 1.2–1.6 letter-spacing for eyebrow labels: `ACTIVE NOW`, `PRIORITY`.
- Direct, short sentences; no "oops" or unearned exclamation marks.
- App names capitalised only as proper nouns.

Contrast (all on `#040404`):
- `#F5F5F5` body — 19.8:1 AAA
- `#6A6A6A` secondary — 5.3:1 AA
- `#1DE9B6` teal accent — 13.2:1 AAA
- Black on teal — 13.2:1 AAA
- Secondary `#A85968` rose, `#3A6B9C` blue — 4.9 / 4.6:1 AA

Touch min 45×45 (exceeds iOS 44, Android 48). Focus ring 1px teal + 2px halo, visible without colour reliance. Motion-reduce ≤80ms. Hit-area +8 px invisible padding.

## 13. Recommended staging — when implementing later

Given scope and risk, the suggested commit-by-commit order (each a separate atomic commit per G1, except where G5 cross-cutting is explicit):

**Stage A — Foundation (tokens, fonts, helpers)**
1. `feat(ui): bundle Sora variable + JetBrains Mono fonts in QRC and load at startup`
2. `feat(theme): add new type scale roles (display/title-L/title-1..3/headline/body/callout/subhead/footnote/caption/eyebrow/mono) with letter-spacing and weights`
3. `feat(theme): add teal-gradient, secondary muted palette, teal-halo, squircle radius`
4. `feat(theme): add reduce-motion dur/ease helpers + platform binding for GNOME/Plasma signals`
5. `chore(build): bump Qt6 minimum to 6.7 (confirm Droidian carries 6.7+)`

**Stage B — Primitives (new components, no surface replacements yet)**
6. `feat(ui): add MMarathonMark (QtQuick.Shapes horizon glyph)`
7. `feat(effects): add GlassBg (MultiEffect backdrop blur wrapper) + TealGlow`
8. `feat(ui): switch Icon.qml from Lucide to Phosphor Light` (cross-cutting — every iconName reference checked)
9. `feat(ui): add MChip, MAvatar, MSearchField`
10. `feat(ui): add MNowBar (live activity strip primitive)`
11. `feat(ui): add MActiveFrame (snapshot + live region primitive)`
12. `feat(ui): add MHUD (system overlay primitive)`

**Stage C — One vertical slice (lock screen)**
13. `feat(shell): rebuild lock screen against new tokens + components (clock 84/200, teal-halo glow, new notification cards)`

**Stage D — Shell surfaces**
14. Status bar, Top bar, Tab bar, Dock — refactor to new specs (one commit each)
15. Hub redesign
16. Quick Settings redesign
17. Active Frames home (new) + behind a feature flag until shipping ready
18. Now Bar wiring (needs LiveActivityManager backend stub)

**Stage E — App rebuilds (one app per commit, biggest impact first)**
19. Phone, Messages, Mail (highest user time)
20. Settings, Music, Camera
21. Calendar, Calculator, Maps, Clock, Gallery, Notes
22. Browser, Store

**Stage F — New surfaces with new backend**
23. Spotlight (AI-native search) — wraps existing UnifiedSearchService + MI placeholder
24. Marathon Intelligence (MI) surface — placeholder until on-device LLM is available
25. Privacy Dashboard — wraps PermissionManager + access log
26. Focus Modes — wraps SettingsManager
27. Wallet — much later; needs hardware-backed identity backend

**Stage G — Cross-cutting renames (do last, once everything else is stable)**
28. `refactor(theme): collapse 6 singletons into one Theme singleton with nested QtObjects` (G5 cross-cutting, ~100 files)
29. `refactor(ui): collapse MarathonUI.{Core,Containers,Controls,...} into single dev.marathon.UI module` (G5 cross-cutting, every app + every shell QML)
30. App icon overhaul — bespoke per-app icons replacing current generic SVGs

## 14. Open questions to confirm before code lands

- **Qt 6.7 minimum** — does the Droidian target have it yet? If not, do we keep Qt 6.4 compat with feature guards (`#if QT_VERSION >= QT_VERSION_CHECK(6,7,0)`) and fall back gracefully?
- **MI backend** — is there one (on-device LLM, prompt API, anything), or do we ship MI surfaces with explicit "preview" / stub state?
- **Wallet** — same question. Hardware-backed identity is multi-week work; do we stub the UI or defer the whole surface?
- **Now Bar source model** — design assumes a shared `LiveActivityManager` aggregating music/call/timer/nav. Build that as part of Stage D before any surface uses it, or stub it?
- **Phosphor Light icon font vs SVGs** — vendor the font and use `font.family: "Phosphor Light"` (smallest binary, one extra font), or vendor SVGs in QRC (works without font loading, larger binary)?
- **Squircle for app icons** — Qt6 has no built-in superellipse path; we'd implement via `QtQuick.Shapes.ShapePath` per `ds-engineering.jsx:552`. Confirm acceptable.
- **`MAppIcon.qml`** — replace existing with new squircle frame, or coexist?
- **Wallpaper variants** — implement all three (Slate Aurora, Carbon, Indigo Dusk), or just Slate Aurora for now?
- **App-icon rebuild** — fully bespoke per app (21 icons) is significant glyph work. Stage F or sooner?
- **OOBE flow** — is the existing `MarathonOOBE.qml` getting rewritten as Language → WiFi → Passkey → Finish? Backend implications (passkey enrolment).

## 15. Quick reference — file map of the handoff

| File | Purpose | Token / spec source for |
|---|---|---|
| `marathon-tokens.css` | All CSS tokens | Definitive token values |
| `design-system/Marathon Design System.html` | Page shell + nav | Just the React boot |
| `design-system/ds-foundations.jsx` | Brand, Overview, Color, Type, Icons, App icon construction, Spacing, Layout, Shape, Elevation, Motion | Token tables + design rules |
| `design-system/ds-components.jsx` | Buttons, Inputs, Cards & Rows, Badges/Chips/Avatars, System bars, Dialogs/HUD, Active Frames, AI surfaces, Voice, Accessibility | Per-component dimensions + behaviour |
| `design-system/ds-engineering.jsx` | Stack & tooling, Theme singleton (full QML), Components in QML (MButton/MRow/MToggle full source), Motion in Qt6, Glass & blur, Assets, Performance | QML implementation templates — **most actionable file** |
| `design-system/ds-styles.css` | Page CSS for the design system docs themselves | Not for shipping |
| `shell.jsx` | StatusBar, StatusBarLock, Dock, HomeIndicator, TopBar, TabBar, AppIcon, Card, Row, Toggle, SectionLabel, AppTile, wallpapers | Shared shell chrome reference |
| `app-icons.jsx` | 21 bespoke app icons + AppIconFrame + registry | App icon reference |
| `screens-shell.jsx` | BootSplash, LockScreen, LockMedia, HomePage1, AppDrawer, TaskSwitcher, QuickSettings, HubScreen, PermissionDialog, IncomingCall, KeyboardActive, SystemHUD | Shell surface layouts |
| `screens-apps-1.jsx` | Settings (+display), Phone, Messages (list+thread), Mail, Browser, Store | App layouts (batch 1) |
| `screens-apps-2.jsx` | Music, Camera, Calendar, Calculator, Maps, Clock, Gallery, Notes, OOBE Language/Wifi/Finish | App layouts (batch 2) |
| `screens-modern.jsx` | ActiveFramesHome, NowBar variants, Marathon Intelligence, Wallet, Focus Modes, Privacy Dashboard, OOBE Passkey, LockNowBar, Spotlight | 2026 modern surfaces |
| `wallpapers.jsx` | All 13 wallpapers (Slate Aurora, Long Run, Track, Mesh, Contour, Stride, Striae, Halftone, Pulse, Dawn, Tundra, Carbon, Indigo Dusk) + shared `Horizon` primitive (`HORIZON_Y = 540`) | Wallpaper specs — see §7 |
| **`Marathon OS.html`** | **Master canvas — 52 numbered artboards across 9 sections** | **Primary entry point per v2 README; defines surface order** |
| `design-canvas.jsx` | `DesignCanvas`, `DCSection`, `DCArtboard` — the canvas chrome | Not for shipping; reads as the order spec |
| `uploads/` | PNG renders, screenshots | Reference only — don't import |

---

**Status:** Analysis complete (v2). No code changed. Branch `ux-overhaul` is at the same HEAD as `alpha-1` (4 atomic refactor commits) ready to receive Stage A foundation work when you give the green light.

**v2 updates from v1 analysis:**
- Canvas (`Marathon OS.html`) is now the authoritative entry point per the v2 README rather than the design-system docs page.
- Section 7 (Wallpapers) expanded from 3-with-stubs to the full **13 documented wallpapers** with their SVG composition.
- Added Section 7a — the master canvas inventory (52 numbered artboards in 9 sections), which doubles as a natural staging order.
- File map (§15) updated to flag `Marathon OS.html` as the primary spec.

The v2 bundle's *file content* (excepting the README pointer and one wallpaper reference screenshot) is byte-identical to v1; this isn't a fundamentally different design, it's the same design with a clearer entry point and the wallpapers fully read.
