# Marathon OS — Per-screen Design Reference

Companion to `ANALYSIS.md`. That doc covers the *system* (tokens, theme structure, module organisation, staging). This doc covers the *designs* — per-screen briefs derived from `screens-shell.jsx`, `screens-modern.jsx`, `screens-apps-1.jsx`, `screens-apps-2.jsx`, **plus** five rendered screenshots from the project owner (Maps, Music Now Playing, LockMedia, Active Frames Home, Task Switcher) that ground-truth the source-derived briefs.

## What ground-truth screenshots changed

The owner shared five rendered screens. Substantive corrections incorporated:

1. **Active Frames *is* the Task Switcher** (BB10 lineage). The handoff drew two separate artboards (`screens-modern.jsx:12` and `screens-shell.jsx:469`) but they are **one surface, one component** — `MFramesView` with `mode: "home" | "switcher"`. Section 04/07 below is merged. **No separate `MTaskSwitcher` to build.**
2. **Lock-screen bottom chrome is NOT the Dock.** Lock variants use a simpler `MLockShortcuts` primitive (phone teal · camera dim · HomeIndicator). The full Dock — with phone/inbox/page-indicator/dots/camera — only appears on Frames, Switcher, Quick Settings, and inside apps.
3. **Maps action cell row has a primary slot.** First cell ("Directions") is fully teal (icon + label); others stay primary-neutral. `MActionCellRow` needs an `accent` flag for the leading cell.
4. **Music tilde and play button are visually larger than the source constants suggest.** Notes adjusted from the literal JSX values to the rendered proportions.
5. **The cast icon on the Music device strip is the concentric-arc broadcasting glyph**, not a generic chevron. Glyph work needs that specific icon.
6. **Calendar frame's "next-up" highlighting is semantic, not a flag.** The next event's time is teal; later events are secondary. Implementation expectation: a `nextItem` semantic on the frame's curated data, not a literal `highlight: true` boolean.
7. **Health rings in the frame are lower-left-anchored**, not centred.
8. **The Frame dock indicator has three explicit states** (numbered circle on home page N, filled square in switcher mode, dim dots for other pages). One component, three modes — `MFrameDockIndicator`.

For each screen: **Layout** (zones, positions, dimensions) · **Hero** (the load-bearing visual decision) · **Novel components** (things not yet in the shell — call out for component-catalog work) · **Reused** (existing primitives) · **Data** (sample content shown) · **Tokens** (key colour, size, blur, radius references).

Canvas is 390 × 844, status bar 28 px, dock area 64 px, tab bar 70 px when present. All `Phone` containers have `borderRadius: 0` (sharp corners — design intent).

---

# Section 1 · Shell (`screens-shell.jsx` + `screens-modern.jsx`)

## 00 · BootSplash (`screens-shell.jsx:11`)

**Layout.** Centred flex column on pure `#000`. No status bar, no chrome.

**Hero.** Teal disc, 96 × 96 px, 50% radius, gradient `linear-gradient(180deg, #1de9b6 0%, #00bfa5 100%)`. Glow `0 0 40px rgba(0,191,165,0.45)` + inset `0 1px 0 rgba(255,255,255,0.3)`, 1 px white-15 border. Black "M" SVG 56 × 56 centred.

**Below disc.** "marathon" wordmark — 14 px, weight 300, letter-spacing 6, uppercase, white. 28 px gap above.

**Progress bar.** Absolute `bottom: 110`, 140 × 2 px, `var(--w-08)` track, teal-gradient fill at 60%, `borderRadius: 1`.

**Novel components.** Nothing — entire screen is two custom items inline.

**Tokens.** `--teal-gradient`, `--w-08`, white-15 border on disc, teal-halo glow.

---

## 01 · LockScreen — clean (`screens-shell.jsx:51`)

**Layout.** Wallpaper (`WallpaperSlateAurora`) + `StatusBarLock` + three absolute zones:
- Clock cluster — `top: 190`, centred
- Notification stack — `top: 420`, `left/right: 18`, flex column gap 8
- Swipe hint — `bottom: 100`, centred
- **LockShortcuts** + HomeIndicator at bottom (see hero section below — NOT the Dock)

**Hero.** Clock "7:08 PM" — **84 px / weight 100 / letter-spacing -2 / line-height 1**, `textShadow: 0 1px 0 rgba(0,0,0,0.5)`. Critical detail: radial halo *behind* the clock — `position: absolute, inset: -28; background: radial-gradient(ellipse at center, rgba(0,191,165,0.20), transparent 65%); filter: blur(8px); zIndex: -1`. Date below — `marginTop: 16`, 15 px / weight 500 / letter-spacing 0.3, `--text-secondary`.

**Bottom chrome on lock is NOT the Dock.** Lock screens (clean / NowBar / media) use **LockShortcuts**: phone icon teal at lower-left, camera icon dim at lower-right, HomeIndicator. No layers/page-indicator button, no dots, no inbox icon. Distinct from `MDock` (used on Frames / Switcher / QuickSettings / app surfaces).

**Notification cards.** 3 stacked. Card 1 (Maya Chen): 32 × 32 icon container (`linear-gradient(180deg, --elev-3, --elev-4)`, radius 4) + name 13 px / 600 + timestamp 11 px secondary right + preview 13 px primary `marginTop: 2`. Card 2 (Calendar): icon background uses `linear-gradient(180deg, #0d0d0e, #1a1b1c)` with `--teal-border`, icon in `--teal-bright`. Card 3 (overflow): "3 more notifications · earlier today", smaller padding (10 × 14), single-row flex with chevron-down.

**Swipe hint.** chevron_up 18 px + "Swipe up to unlock" 13 px / `marginTop: 4` / letter-spacing 0.3.

**Novel components.** The teal radial halo behind the clock is the signature treatment — needs a reusable "haloed display" primitive.

**Reused.** StatusBarLock, Card, Icon, LockShortcuts, HomeIndicator, WallpaperSlateAurora.

**Data.** 7:08 PM · Fri Dec 5 · Maya "Heading out, see you at 8 — saved a spot near the back" · Calendar "Design review — Studio B" in 22 m · 3 collapsed.

**Tokens.** Halo `rgba(0,191,165,0.20)` + `blur(8px)`. Cards `elev={2}`.

---

## 02 · LockNowBar — call active on lock (`screens-modern.jsx:698`)

**Layout.** Wallpaper + `StatusBarLock` (no time). **Oversized Now Bar** at `top: 70, left/right: 16` — larger than home variant. Clock at `top: 220` (76 px / weight 100, smaller than clean lock). Health rings card at `top: 410, left/right: 16`. Unlock hint `bottom: 100`. **LockShortcuts** + HomeIndicator.

**Hero.** The Now Bar in call state. Larger padding (`14 × 16` vs. home's `0 12 0 6`). Icon badge **44 × 44 px** (vs. 26 on home) with gradient `linear-gradient(180deg, #1a4a3e, #0d2620)`, 1 px `--teal-bright` border, pulse ring `position: absolute; inset: -4; border: 1px teal; opacity: 0.4`. Phone icon 20 px inside.

**Text.** Eyebrow "CALL · 02:14" 11 px teal-caps, "Maya Chen" 15 px / weight 600.

**End button.** 36 × 36 circle right side, `background: var(--error)`, phone icon rotated 135°.

**Health rings widget.** Card 14 px padding, flex row gap 14:
- SVG rings 60 × 60 — three concentric arcs (Move rose `#a85968` r=24, Exercise teal `#1de9b6` r=17, Stand blue `#3a6b9c` r=10), stroke-width 5, `transform: rotate(-90 ...)` to start at top, `strokeDasharray + strokeDashoffset` for fill percentage.
- Right column: eyebrow "ACTIVITY" 12 px secondary 0.5 spacing, "Move 74% · Stand 79%" 16 px / 500, "1 ring left to close before bed" 12 px secondary.

**Novel components.** **MNowBar** call variant (with pulse ring + end button). **HealthRings** SVG widget (also used on ActiveFrames home).

**Tokens.** Pulse `rgba(0,191,165,0.4)` 1 px border. End button `--error`. Ring colours fixed `#a85968 / #1de9b6 / #3a6b9c`.

---

## 03 · LockMedia — music widget on lock (`screens-shell.jsx:165`)

**Layout.** Wallpaper + `StatusBarLock`. Clock cluster `top: 170` (76 px / weight 100 / letter-spacing -1.5, halo `blur(6px)` slightly softer than clean lock). Media widget Card `top: 360, left/right: 18`. Swipe hint + **LockShortcuts** (phone teal · camera dim, no centre indicator) + HomeIndicator.

**Hero.** The media widget. Card with **`background: linear-gradient(180deg, rgba(0,89,77,0.25), rgba(0,89,77,0.10))`** + 1 px `--teal-border`, `elev={2}`. Padding 14.

Top section (flex row gap 14): album art 64 × 64 / radius 4 with gradient `linear-gradient(135deg, #1a4a3e 0%, #0d2620 100%)` and signature **scan-line overlay** `repeating-linear-gradient(90deg, transparent 0, transparent 3px, rgba(29,233,182,0.15) 3px, rgba(29,233,182,0.15) 4px)` — vertical hairlines every 3–4 px. Music icon 24 px teal-bright inside. Beside: title 15 px / 600, artist 13 px secondary `marginTop: 4`.

Scrubber row (`marginTop: 14`): "4:32" left + thin 3 px track `var(--w-08)` with teal-gradient fill at 38%, 10 × 10 white-tealish circular thumb `boxShadow: 0 0 8px var(--teal-glow)` at the 38% point + "11:48" right. Times 11 px tabular.

Controls row (centred, `gap: 22, marginTop: 14`): skip_back (50 px secondary `CircButton`) → **~60 px primary `CircButton` (teal-gradient + halo glow) showing play arrow — visually larger and more prominent than the skip buttons; the lock-screen prioritises the resume affordance** → skip_forward.

**`CircButton` definition (`screens-shell.jsx:256`).** 50 × 50 circle (primary), border `1px solid rgba(255,255,255,0.15)`, `background: var(--teal-gradient)` (primary) / `var(--elev-3)` (secondary), shadow `0 0 20px rgba(0,191,165,0.45), inset 0 1px 0 rgba(255,255,255,0.3)`.

**Novel.** Scan-line album art is reusable. CircButton primitive.

**Data.** 11:42 AM, Fri Dec 5, "How Fast Is The Analogue 3D" by James Lambert, 4:32 / 11:48.

---

## 04 / 07 · ActiveFrames — Home and Task Switcher are the SAME surface

The handoff renders these as two screens (`screens-modern.jsx:12` ActiveFramesHome and `screens-shell.jsx:469` TaskSwitcher). **They are one surface**, per BB10 lineage: Active Frames *is* the task switcher. The designer drew two artboards but the implementation collapses them. One `MFramesView` component renders both — the difference is content mode + dock indicator state.

### The unification

| | "Home" mode (screen 04) | "Switcher" mode (screen 07) |
|---|---|---|
| **Frame chrome** | Header bar at *top* (icon + app + count) | Title bar at *bottom* (icon + app + state + close X) |
| **Frame body** | Curated widget — the app's "next thing" (Calendar's NEXT event highlighted teal, Music's NOW playing, Health's TODAY rings, Messages' UNREAD list) | Live snapshot — the app's last view (Browser's article, Messages' conversation list, Calendar's month grid, Music's now-playing widget) |
| **Dock centre** | White circle with page number ("1") | White square (filled) with layers icon, no number |
| **Greeting block above grid** | "FRIDAY · DECEMBER 5" + "Good morning, Avery" | Absent — frames fill more vertical space |

Both share: the 2 × 2 grid (`top: 168` in home mode, `top: 44` in switcher mode), gap 10, frame size, glass treatment, NowBar at top, dock at bottom, swipe-between-pages of frames.

Apps therefore provide **two slots**: a `widget` slot (curated state) and a `preview` slot (last view). The view picks which to render based on mode. No separate "home page" vs "task switcher" state in the shell.

### Common frame anatomy

- Background `rgba(22,23,24,0.78)`, `backdrop-filter: blur(16px)`
- Border 1 px `var(--w-08)`, radius 4
- Shadow `inset 0 1px 0 var(--w-06), 0 6px 18px -8px rgba(0,0,0,0.5)`
- Fixed height 158 (frames don't grow with content — content truncates)
- Flex column

### Home-mode content variants (curated)

- **Calendar.** Top header: 14 px calendar icon (teal) + "Calendar" 12/600 + "3 today" 10 secondary right. Three event rows below: each is `time` (50 px right-aligned tabular, **teal-bright on the NEXT event, secondary on later events** — this is the `nextItem` semantic, not just an arbitrary highlight flag) + event title 12/500 + gap 10. Three rows: 12:00 Design review (teal next-up), 15:30 1:1 Devon, 19:30 Concert · Bowery.
- **Music.** Top header: music icon teal + "Music" 12/600 + "Playing" 10 teal-bright. Body: 44 × 44 album-art square `linear-gradient(135deg, #1a4a3e, #0d2620)` + music icon teal centred. Beside it: "Modular Tides" 11/600 + "Avior" 10 secondary. Below: 3 px progress bar `var(--w-08)` track, teal fill at 42%, no thumb.
- **Health rings.** Top header: heart icon **rose** (`#a85968` — not teal — per the `secRose` semantic for Health throughout the system) + "Health" 12/600 + "2 of 3" 10 secondary right. Body: SVG 74 × 74 rings, **positioned lower-left within the frame body**, leaving upper-right negative space. Concentric: Move rose r=30 stroke 5 60% fill, Exercise teal r=22 75% fill, Stand blue r=14 37% fill. All `transform="rotate(-90 ...)"` to start at top, `stroke-linecap: round`.
- **Messages.** Top header: chat-bubble icon **sec-blue** (`#3a6b9c`) + "Messages" 12/600 + "3 unread" 10 secondary right. Body: 3 preview rows — `name` 11/600 + `snippet` 11/secondary single-line ellipsis, gap 10. Maya / Devon / Linear.

### Switcher-mode content variants (snapshots)

- **Browser.** Article preview region (dark area + "POPULAR TOPICS" teal pill banner 9 px + mock headline "Marathon OS 4.2 brings deeper Hub integration" + byline + first-line snippet).
- **Messages.** 3 row mini-preview of last conversation list (avatar square + name + snippet repeated).
- **Calendar.** Month grid (7-col day-letter row + 35 cells, today highlighted teal).
- **Music.** Teal-gradient body + 60 × 60 album-art mini + "Modular Tides" 9/bold + "Avior" 8/secondary + 3 controls (skip / pause / skip 10 px each).

Title bar at the bottom of each switcher card: 52 px high, glass-tabbar background, 28 × 28 elev-3 icon container + title 12/600 + subtitle 10/secondary + close X 14 px.

### Pinned dock row (home mode only)

`bottom: 88, left/right: 16, gap` even. 4 squircle app tiles + label below each. Phone (teal-gradient bg + phone icon white), Messages (dark + teal speech-bubble), Mail (dark + teal envelope outline), Browser (dark + teal globe). Tile ~56 × 56, label 12/500.

### Bottom dock chrome (both modes)

Phone icon teal far-left → inbox icon dim → **page indicator centre** → 3 dim dots → camera icon dim far-right → HomeIndicator.

**Page indicator** states:
- *Home mode, page N of frames:* `32 × 32 white circle, radius 4, white fill, black layers icon + "N" text` (e.g. "1" — currently on page 1).
- *Switcher mode:* `32 × 32 white square, radius 4, white fill, black layers icon, no number`.
- *Other pages:* `8 × 8 dim circle dots` `--w-24`.

### Now Bar

Same as screen 02. On Frames home, music variant — icon badge 26 × 26 + "Modular Tides" / "Avior · 1:48" + 5-bar visualiser (`[6, 10, 4, 8, 5]` heights, `--teal-bright`, alternating opacity 0.5/1.0, gap 2).

### Novel components (heavy)

- **MFramesView** — the 2 × 2 grid container, manages page model, snaps between pages, mode-aware (home vs switcher).
- **MActiveFrame** — single frame container with `mode` prop (`"home"` or `"switcher"`), `header`/`titleBar` slots, `widget`/`preview` body slots. App registers both; frame picks based on `mode`.
- **MFrameDockIndicator** — the page/state indicator in the bottom dock (number-in-circle vs square-active vs dim dots).
- **HealthRings** SVG primitive (also used on LockNowBar).
- **MNowBar** music variant with visualiser.

### Tokens
Frame glass `rgba(22,23,24,0.78)` + `blur(16px)`. Ring colours fixed (`#a85968 / #1de9b6 / #3a6b9c`). Next-event time teal-bright; later-events secondary.

---

## 05 · HomePage1 — legacy 4 × 4 app grid (`screens-shell.jsx:369`)

**Layout.** Wallpaper + StatusBar. Marathon mini-lockup `top: 36, left: 18` (18 × 18 teal-gradient box with M + "Marathon" 10 px uppercase 2 px tracking). **App grid** `top: 80, left/right: 16, bottom: 100`, CSS grid `repeat(4, 1fr)`, rowGap 18, columnGap 8, align-content start, justify-items center. Dock + HomeIndicator at bottom (dock shows page indicator).

**Hero.** The grid itself — 16 `AppTile`s (4 × 4). Each tile = squircle icon (per-app gradient + glyph from `app-icons.jsx`) + 12 px / 500 label. Calendar tile is special: shows "FRI" 9 px / 700 white + "5" 22 px / 200 teal directly on the gradient (no separate glyph).

**Apps shown.** Phone, Messages, Mail, Browser, Store, Music, Camera, Gallery, Maps, Calendar, Clock, Calculator, Marathon, Wallet, Health, Settings.

**Reused.** WallpaperSlateAurora, StatusBar, AppTile, Dock, HomeIndicator.

---

## 06 · AppDrawer (`screens-shell.jsx:391`)

**Layout.** Wallpaper (**Carbon** variant — calmer for browsing) + StatusBar. Header block padding `18 20 8`: "All Apps" `screen-heading` (34 px / 200 / -0.8) + search box `marginTop: 12, height: 38, radius var(--r-md)`, background `--bb10-elevated`, border `1px --w-04`, flex row with 16 px search icon + "Search apps" placeholder. Below: flex column, padding `8 16`, overflow hidden — A/B/C/D alphabetical sections.

**Each section.** Letter heading 11 px / 700 / `--teal-bright` / 1 px tracking, padding `4 4 6`. `Card` wrapping `.m-row` rows for each app. Each row: 36 px app icon (real `APP_ICON_COMPONENTS` rendered, or fallback note-icon row-icon 18 px) + title + chevron_right 16 px tertiary right. Padding 10 × 14.

**Reused.** WallpaperCarbon, StatusBar, Card, Icon, APP_ICON_COMPONENTS, HomeIndicator.

---

## 07 · ~~TaskSwitcher~~ — collapsed into Active Frames (see §04 / 07)

The handoff renders this as a separate screen but **it's the same surface as ActiveFramesHome**, in switcher mode. See the merged section above. The handoff's `TaskSwitcher` artboard is `MFramesView` with `mode="switcher"`; the screen-04 artboard is the same view with `mode="home"`. No separate implementation.

---

## 08 · QuickSettings (`screens-shell.jsx:613`)

**Layout.** Wallpaper opacity 0.32 (dimmed) + dark gradient overlay `linear-gradient(180deg, rgba(13,13,14,0.95), rgba(13,13,14,0.86) 65%, rgba(13,13,14,0.7))`. StatusBar. **Glass panel** `inset: 0, top: 28` — `var(--glass-titlebar)` + `backdrop-filter: blur(24px)`, border-bottom `1px var(--border-glass)`, padding `14 16 0`, flex column.

**Top row** (padding `0 2 14`, space-between): Marathon mini-lockup left + "Fri · 7:08 PM" 13 px secondary right.

**Sliders block** (`--elev-2` background + `1px --w-04` border, padding `12 14`, marginBottom 14): Brightness slider + 1 px divider + Volume slider.

**`QSSlider`.** Flex row, gap 12. 18 px icon. Right column: label row ("BRIGHTNESS" 11 px / 600 / uppercase secondary + value 11 px / 600 tabular primary). Bar 4 × 4 `var(--w-08)` track, teal-gradient fill at value%, 14 × 14 white thumb with `boxShadow: 0 2px 4px rgba(0,0,0,0.4), 0 0 8px var(--teal-halo)` translated by `-50%, -50%` at value%.

**Tile grid** (2 cols, gap 8) — 6 visible of 10. Each tile is `QSTile` (Wi-Fi, Bluetooth, Mobile data, Flight mode, DnD, Torch).

**`QSTile` — signature BB10 split-bay** (`screens-shell.jsx:802`):
- Height 64. `--elev-2` background. Border 1 px `--teal-border` if on else `--w-04`. Shadow `0 0 10px rgba(0,191,165,0.18) + inset 0 1px 0 var(--w-04)` if on, else inset only. Radius 4.
- Left bay 60 px, `flexShrink: 0`. Background `--teal-bright` if on else transparent. Icon centred, stroke 2 if on else 1.6, black if on else tertiary. Border-right `1px --teal-border` if on else `--w-04`.
- Right bay flex 1, padding `0 14`, flex column justify-center. Label 13 px / 600 bold-if-on else secondary. Sub-status 11 px teal-bright if on else tertiary.

**Page indicator** (`marginTop: 14`, centred, gap 6): active page = teal **bar** 18 × 4, next = 4 × 4 circle.

**Now-playing strip** (`marginTop: 14`, padding `10 14`, gradient `linear-gradient(180deg, rgba(0,89,77,0.22), rgba(0,89,77,0.06))`, `1px --teal-border`, radius 4): 36 × 36 album art + song title 13 / 600 + artist 11 secondary + 3 controls (skip 15 px, 28 × 28 teal play, skip 15 px).

**Drag handle** (`marginTop: auto, paddingBottom: 14, paddingTop: 16`, centred): 44 × 4 bar `--w-12`, radius 2.

**Novel.** **QSTile** split-bay is the most distinctive new pattern in QS. **QSSlider** with halo'd thumb. Page-bar-not-dot indicator.

---

## 09 · HubScreen — unified inbox (`screens-shell.jsx:859`)

**Layout.** Wallpaper (**Carbon**) + StatusBar. **Header** `top: 28, height: 132` — `--glass-actionbar` + `blur(20px)` + border-bottom. Padding `14 20 0`. Title row: "Hub" 32 px / 200 / -0.6 + "12 unread" 13 px secondary on left; search + filter icons 20/19 secondary right. **Chip filter row** below title (padding `16 20 0`, flex gap 6, overflow-x hidden): "All" (active = teal-bright bg, black text, teal border), others (transparent bg, secondary text, `1px --w-08` border). Padding `7 14`, radius 999. Each chip = label + count.

**List area** `top: 160, bottom: 0`. `HubGroup` labels padding `14 20 6` — 11 px / 600 / uppercase / 1.2 spacing / secondary ("Today", "Yesterday").

**`HubRow2`** (the unified row, `screens-shell.jsx:971`):
- Min-height **72**. Flex gap 14. Padding `14 20`. Align centre.
- Optional **unread dot** 8 × 8, radius 50%, `--teal-bright`, glow if unread, `marginLeft: -4` to overlap left edge.
- **Avatar** 40 × 40, radius 50%, tint per contact, `1px --w-08` or `--teal-border` for special. Monogram 14 / 500, or phone icon 18 px for missed calls.
- Content (flex 1, minWidth 0):
  - Name row (justify-between, gap 10): name 15 / 600 (unread) or 500 (read) primary, ellipsis + time 12 secondary tabular flex-shrink 0.
  - Account label 12 secondary `marginTop: 2`.
  - Snippet 13 primary-if-unread else secondary, `marginTop: 4`, single-line clamp.

**Rows shown.** Maya (iMessage, #3a6b9c tint, unread), Linear (Work, #6b5d8f, unread), Cassandra Reyes (Mail, #a85968), Missed call · Devon (phone icon + `--teal-bright`, 2 attempts), GitHub (mono, teal-border).

**Chips.** All 12, Messages 3, Mail 5, Work 2, Calls 2.

**Novel components.** **MHubRow** (avatar + name+time / account / snippet pattern). **MFilterChipRow** (pill chips with active state).

---

## 10 · Spotlight — AI-native search (`screens-modern.jsx:793`)

**Layout.** Wallpaper + dark gradient overlay `linear-gradient(180deg, rgba(4,4,4,0.65), rgba(4,4,4,0.92))`. StatusBar. **Search field** `top: 60, left/right: 16, height: 56`. Body `top: 144, left/right: 16, bottom: 20`, flex column gap 16. Privacy footer text at bottom.

**Search field.** Radius 4, background `rgba(13,13,14,0.85)`, `blur(20px)`. Border `1px --teal-border`. Shadow `0 8px 30px -8px rgba(0,0,0,0.7), 0 0 22px var(--teal-halo), inset 0 1px 0 var(--w-06)`. Flex row: Marathon mark 20 px teal + query "concert friday" 17 px / 400 + **blinking cursor 2 px wide, teal, `boxShadow: 0 0 6px var(--teal-glow)`** + mic icon 20 px secondary right.

**Hero — AI Answer card.** Padding 18. Background `linear-gradient(135deg, rgba(0,191,165,0.12), rgba(0,191,165,0.03) 75%)`. Border 1 px teal. Inset shadow.
- Header row: 22 × 22 Marathon badge (teal gradient) + "Marathon Intelligence" 11 px / 600 teal 0.5 spacing + "on-device" 10 px tertiary.
- Answer text 15 px / 1.55 line-height: bolds key phrases, inline **citation badges** as superscript boxes (16 × 16, radius 4, `--teal-bright` bg, black 10 px / 700 number, `vertical-align: top, margin: 0 2px`).
- Divider, then **source row** flex gap 14: each source = numbered box (same 16 × 16 teal) + 12 px icon secondary + name 13 px primary / 500.

**Top Hit card.** "Top hit" 11 px caps label. Card padding 16, radius, background `rgba(22,23,24,0.75)` + `blur(12px)`, 1 px `--w-08`. 44 × 44 icon badge (teal in `rgba(0,191,165,0.18)`) + "Concert · Bowery" 15 / 500 + "Tonight, 7:30 PM · 4 attendees" 13 secondary + chevron right.

**More Results.** "More results" caps. SpotRow ×3 — 36 × 36 tinted icon (blue/rose/green) + title 14 / 500 + subtitle 12 secondary, 1 px top divider per row.

**Privacy footer.** Centred "Searches stay on this device" 11 tertiary 0.3 spacing.

**Novel components.** **MSearchField** (the haloed search bar with cursor). **MAIAnswer** (gradient panel + citation system). **MCitationBadge** + **MSourceRef** primitives.

**Tokens.** AI panel gradient. Citation badge teal/black. Search-field halo `0 0 22px var(--teal-halo)`.

---

# Section 2 · Marathon Intelligence (`screens-modern.jsx`)

## 11 · MarathonIntelligence assistant (`screens-modern.jsx:259`)

**Layout.** AppShell (status bar). Custom 88 px titlebar padded `0 18, align-end, paddingBottom: 14`. Content `top: 116, left: 0, right: 0, bottom: 70`, padding `14 16`, overflow hidden. Input zone `absolute, left: 16, right: 16, bottom: 12`.

**Titlebar.** Left: 32 × 32 teal-gradient square badge, `boxShadow: 0 0 18px var(--teal-halo)`, inset highlight, zap-bolt icon black inside + "Marathon" 22 / 200 + "On-device · listening" 12 teal.

**Suggestion cards.** 2-col grid, gap 8, padding 12 — Each `SuggestCard`:
- Background `--elev-2`, border `1px --w-04`, inset + outer shadow.
- 26 × 26 icon (NOT circle, square radius 4) — solid tint background per card.
- Title 13 / 600 + description 11 secondary, gap 8 flex column.
- 4 cards: "Leave by 11:48" (teal tint), "Reply to Maya" (blue), "Stand goal" (rose), "Tomorrow is light" (teal).

**Conversation bubbles.**
- User: `align-self: flex-end, max-width: 85%`, `--elev-3` background, `1px --w-08` border, padding `8 12`, radius (default), 13 px / 1.45.
- AI: `align-self: flex-start`, no background or border, padding `4 0`, same font.
- Action button row after AI: gap 6 wrap. Primary = teal-gradient + black text + 0.3 opacity teal glow shadow. Secondary = `--elev-2` + `--w-08` border + primary text. Padding `6 12`, font 12 / 600.

**Input zone.** Pill: flex 1 / 44 px / radius **22** (pill, not 4) / `--bb10-surface` bg / `1px --w-08` / padding `0 16` + 14 px hint placeholder. Send button 44 × 44 teal-gradient circle, mic 20 px black.

**Novel components.** **MSuggestCard**, **MAIBubble** (with user/AI variants), **MAIActionRow** (primary+secondary chips), **MMicInput** (pill input + send circle).

**Data.** Suggestions tied to calendar/messages/health/calendar. Conversation: user asks route to Studio B, AI proposes walking 7-min route via Madison with order-coffee option.

---

## 12 · WalletApp (`screens-modern.jsx:410`)

**Layout.** AppShell + standard TopBar ("Wallet", search, teal **plus** square button). Content `top: 116, left: 0, right: 0, bottom: 70, padding: 14 16, overflow hidden`. **Stacked cards section** `height: 250, marginBottom: 18`. Passkey section below. TabBar bottom (3 tabs).

**Hero — stacked card pile.** 3 absolute cards, each `top: i * 38`, `height: 180`. Top card (Marathon ID) fully visible; lower cards peek.
- **Marathon ID**: gradient `linear-gradient(135deg, #1a4a3e 0%, #040404 100%)`. Padding `14 18`. Top: label "MARATHON ID" 10 caps secondary + verified badge `padding: 3 8, --teal-bright bg, black 10 / 700, "VERIFIED"`. Subtitle "Avery Rhodes" 14 / 600 white. Bottom row: 44 × 44 "AR" monogram circle (teal text) + name 13 white + URL "marathon.id/avery" 10 alpha-0.5.
- **Bank Debit**: light gradient. "•••• 4192".
- **Transit Metro**: dark gradient. "Balance $24.50".

Each card: shadow `0 12px 24px -8px rgba(0,0,0,0.6), inset 0 1px 0 var(--w-12)`.

**Passkey list.** Card wrapper (overflow hidden). 3 rows: domain (14 px) + email · last-used (secondary). 40 × 40 row-icon `--elev-3` with shield icon teal. Chevron right.

**Novel.** **MStackedCardPile** primitive (absolute offset stacking). **MVerifiedBadge** chip.

---

## 13 · FocusModes (`screens-modern.jsx:500`)

**Layout.** AppShell + TopBar (title, back, plus add). Content `top: 116, bottom: 0, padding: 14 16`. Active mode hero card (marginBottom 18). "All modes" Card list.

**Hero — active mode card.** Padding 18. Background `linear-gradient(135deg, rgba(58,107,156,0.16), rgba(58,107,156,0.04))` (blue tint at 16% — picks up sec-blue for Sleep). Border `rgba(58,107,156,0.35)`.
Flex row gap 14:
- 56 × 56 circle icon, radius 50%, background `rgba(58,107,156,0.18)`, border `rgba(58,107,156,0.45)`, glow `0 0 20px rgba(58,107,156,0.30)`, icon `#7da3cb`.
- Right column: "ACTIVE NOW" 11 / 600 / blue / 1 px tracking eyebrow, mode name 20 / 500, "Until tomorrow at 7:00 AM" 12 secondary.
- Far right: "End" ghost button, 32 px high.

**Effect chips row** below: muted `m-chip` style ("DnD on", "Grayscale", "Hub muted", "Alarms only").

**Mode list.** Card with 5 m-rows. Per row: icon (tint-coloured 16 px in 32 × 32 tint background) + name (title) + schedule (subtitle) + Toggle right. Mode colours: Work teal, Sleep blue, Driving amber, Reading violet, Workout rose.

**Novel.** **MModeHeroCard** (tinted gradient + glow-circle pattern). Heavy reuse of MRow/Toggle.

---

## 14 · PrivacyDashboard (`screens-modern.jsx:563`)

**Layout.** AppShell + TopBar ("Privacy", back, info). Content `top: 116, bottom: 0, padding: 14 16`. 3 sections: privacy-score hero, recent-access, identity.

**Hero — privacy score card.** Card with privacy-score ring on left (72 × 72 SVG):
- Outer circle r=30, `stroke: var(--w-08), stroke-width: 4`
- Active arc same r/stroke but `var(--teal)`, `stroke-dasharray: 188.5, stroke-dashoffset: 56.5` (70% fill)
- Centred text "70" 18 / 600 primary at (36, 40)
Right column: "Privacy score · Strong" headline + "3 apps with broad permissions you might want to review" 12 secondary.

**Recent access list.** Card with 4 m-rows. Each: 40 × 40 tinted square (camera amber, location teal-on-black, mic rose, contacts blue) + permission name 14 + "App · time · duration" subtitle. Chevron.

**Identity section.** 3 standard Rows: "Passkeys & sign-in (12 saved)", "Hide my email (42 aliases)", "Tracking report (0 cross-site today)".

**Novel.** **MScoreRing** SVG primitive.

---

# Section 3 · System Overlays (`screens-shell.jsx`)

## 15 · PermissionDialog (`screens-shell.jsx:1028`)

**Layout.** Wallpaper at opacity 0.35 + black scrim `rgba(0,0,0,0.72)`. **Modal Card** absolute centred via `top: 50%; transform: translateY(-50%); left/right: 24`. Background `--elev-2`. Overflow hidden. Elevation 4. StatusBar + HomeIndicator persist.

**Hero — app info block** (padding `24 22 18`, flex row gap 16, align-centre):
- 64 × 64 app icon container, radius 4. Contains `MarathonAppMark`. Shadow `0 0 0 1px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.12)`.
- App name 20 / 500 / -0.3 + developer 13 secondary `marginTop: 2`.

**Permission row.** m-row with border-top/border-bottom `1px --w-04`. Storage icon + "Storage" title + "Read and write your files" subtitle. No chevron.

**Explanation text** padding `16 22 4`, 14 / 1.5 primary: *"Slate Notes wants to save attachments and exports to your Documents folder."*

**Subtext** padding `4 22 0`, 12 secondary 1.5 line-height: *"You can change this anytime in Settings → Apps → Slate Notes."*

**Action buttons.** Padding 16, flex row gap 10. "Deny" secondary flex 1 + "Allow" primary flex 1.

**Novel.** Pattern is mostly reused, but the app icon at the top with developer line is a permission-dialog signature.

---

## 16 · IncomingCall (`screens-shell.jsx:1083`)

**Layout.** Wallpaper + radial teal glow overlay `rgba(0,89,77,0.22)` ellipse 70% fade. StatusBar. "INCOMING CALL · MOBILE" eyebrow `top: 100`, 13 / secondary / 1 px tracking / uppercase. **Caller avatar** at `top: 160`. Name + number below. **Quick reply chips** at `bottom: 220`. **Accept/Decline buttons** at `bottom: 80`. HomeIndicator.

**Hero — caller avatar.** Circle 130 × 130 px, gradient `linear-gradient(180deg, #1a4a3e, #0d2620)`, 2 px `--teal-border`, shadow `0 0 40px rgba(0,191,165,0.35), inset 0 1px 0 var(--w-12)`. Monogram "DP" 50 / 200 / `--teal-bright`. **Two pulse rings** absolutely positioned `inset: -16` and `inset: -28`, radius 50%, `border: 1px --teal-border`, opacity 0.6 / 0.3.

**Below avatar.** "Devon Park" 30 / 200 / -0.5 / `marginTop: 24`. "+1 (415) 555-0142 · San Francisco" 14 / secondary `marginTop: 6`.

**Quick reply chips** (3, flex-wrap): padding `8 14`, radius 4, `--elev-2` bg, `1px --w-08` border, 13 primary. "I'll call you back" / "In a meeting" / "On my way".

**`CallButton`** (72 × 72 circle):
- Primary (Accept): `--teal-gradient` bg + glow `0 0 24px rgba(0,191,165,0.5), inset 0 1px 0 rgba(255,255,255,0.3)`. Phone icon 32 px black.
- Decline: `--error` bg + glow `0 0 24px rgba(239,68,68,0.4), inset 0 1px 0 rgba(255,255,255,0.2)`. Phone icon 32 px white, **transform: rotate(135deg)**.
Both have 1 px white-15 border. Label 13 / secondary / uppercase / 1.5 spacing below at `marginTop: 10`.

**Novel.** **MCallerAvatar** with pulse rings. **MCallButton** primary/decline variants.

---

## 17 · SystemHUD (`screens-shell.jsx:1312`)

**Layout.** Background simulates music app: wallpaper + overlay gradient `linear-gradient(180deg, #1a4a3e, #040404 60%)` opacity 0.6 + faint 260 px album-art placeholder behind. StatusBar. **HUD card** `left/right: 20, top: 60`, padding `14 18`. Background `--glass-titlebar` + `blur(16px)`. Border `1px --border-glass-strong`. Shadow `0 12px 30px -10px rgba(0,0,0,0.7), inset 0 1px 0 var(--w-06)`. Elevation 3.

**Content.** Flex column gap 10:
- Title row: volume icon 22 px teal-bright + "MEDIA VOLUME" 13 / secondary / 0.4 spacing + value "62" 18 / 300 tabular primary right.
- Bar 6 × full, `--w-08` track, teal-gradient fill at 62%, `boxShadow: 0 0 12px var(--teal-glow)`. Radius 3.

**Novel.** **MHUD** primitive (transient floating glass card pattern, used here for volume — same shape for brightness, etc.).

---

## 18 · KeyboardActive (`screens-shell.jsx:1178`)

**Layout.** StatusBar at top. **Message view** `top: 28, bottom: 290` — `--bb10-black` background, padding `12 16`, flex column gap 8. **Keyboard area** `bottom: 0, height: 290` — `--glass-tabbar` + `blur(14px)` + border-top, padding `8 6 28`.

**Prediction strip** (flex gap 8, padding `4 8`, justify-between, border-bottom): 3 words ("Awesome" / "30 min" / "about"). Each flex 1 textAlign centred, 13 primary, padding `6 0`, radius 4. **First (selected): `--elev-2` background + `1px --teal-border` + weight 600**, others transparent / 400.

**Keys.**
- **KbRow**: flex row gap 4, padding `4 0`, justify-centre. Optional **shift** key (wide, highlight) with arrow_up icon + letter keys + optional **delete** key (wide, highlight) with X icon.
- **KbBottomRow**: flex row gap 4, padding `4 0`. "123" wide highlight + globe wide + **space flex 4** "space" 12 secondary + period + **send key flex 0 0 58** teal-gradient with send icon black + glow shadow.

**`Key`** dimensions: height 42, radius 4. Background `--elev-3` if highlight else `--bb10-surface`. Border `1px --border-glass`. Shadow `inset 0 1px 0 var(--w-04), 0 1px 0 rgba(0,0,0,0.4)`. Flex-centre 16 px primary 400 weight. Width: `flex: 0 0 42px` if wide, else `flex: 1`.

**`Bubble`.** Flex child align-self end/start by `me` flag, max-width 78%.
- Name label 11 px secondary `marginLeft: 4` `marginBottom: 3` if not me + name provided.
- Bubble: teal-gradient if (me && !composing) else `--elev-2`. Text black or primary. Padding `8 12`, radius 4. Border `--teal-border` if (me && composing) else `--w-04`. 14 / 1.35.
- Composing state adds 2 px left border `--teal-bright`, `marginLeft: 4` (cursor).

**Novel.** **MKeyboard** (with prediction row + 4 rows + send + space). **MBubble** (with status indicator + composing cursor).

---

# Section 4 · OOBE (`screens-apps-2.jsx` + `screens-modern.jsx`)

## 19 · OOBELanguage (`screens-apps-2.jsx:850`)

**Layout.** Wallpaper at opacity 0.4 + black floor. StatusBar (time "—", battery 100). Top padding `50 28 24`. Heading block: globe icon 48 px teal-bright, "Choose your language" 36 / 200 / -0.8 / line-height 1.05, description 14 secondary. **Language Card** scrolls `top: 290, bottom: 110`. **Footer bar** absolute bottom padding `14 26`: "Step 1 of 5" 12 secondary + Continue button (primary, 44 px, padding 26, chevron right at end). HomeIndicator.

**Card content.** 8 m-rows. Each: language name + region as subtitle. Checkmark teal-bright if selected (default: English US).

**Tokens.** Wallpaper alpha 0.4. Heading weight **200**.

---

## 20 · OOBEWifi (`screens-apps-2.jsx:909`)

**Layout.** Same scaffolding as Language. Heading "Get connected" + description. Card scrolls. Connection status text 12 secondary below card. Step 2 / 5 footer + Continue.

**Network rows.** Each m-row: wifi icon in row-icon circle. **Selected row uses `rgba(0,191,165,0.15)` background + `--teal-border` border**; unselected uses `--elev-3`. Title (SSID) + "Signal X/5 · WPA2" subtitle. Checkmark for selected, lock icon for secured-not-selected.

**Data.** 6 networks (Marathon-Mesh selected, Marathon-Guest, CafeBleu_5G, eduroam, xfinitywifi, Pixel_2A1B). Connection status: "Connected to Marathon-Mesh · 2.4 Mbps download".

---

## 21 · OOBEPasskey — biometric setup (`screens-modern.jsx:618`)

**Layout.** Black background + wallpaper at opacity 0.4. StatusBar. Header area padding `50 28 24`: 48 × 48 teal-gradient icon-square (shield, glow). "No more passwords" 36 / 200 / -0.8 heading + description.

**Biometric card** `top: 320, left/right: 24`, padding 22, centred:
- 84 × 84 circle, `border-radius: 50%`, background `--bb10-deep`, **2 px teal border**. Custom SVG fingerprint 36 × 40, teal stroke, stroke-width 1.7 round caps.
- **Pulse halo** `position: absolute, inset: -10, border: 1px teal, opacity: 0.4`.
- Below: "Set up Touch ID" 18 / 500. Description "Place your finger on the sensor a few times…" 13 secondary.
- **Progress strip** 6 bars × 24 × 4 px. Filled bars: `--teal-bright` + `0 0 6px var(--teal-glow)`. Unfilled: `--w-08`. Pattern: `[filled × 3, unfilled × 3]` (3 of 6 scans complete). Below: "3 of 6 scans complete" 11 tertiary.

**Footer.** Step 4 of 6.

**Novel.** **MBiometricSensor** primitive (circle + SVG fingerprint + halo + progress bars).

---

## 22 · OOBEFinish (`screens-apps-2.jsx:978`)

**Layout.** Black + **WallpaperIndigoDusk** at opacity 0.7 (richer than Lang/Wifi). Radial teal glow 380 × 380 at 35% top, 25% opacity. StatusBar. Centred flex column, padding 36 h:
- **Check circle 110 × 110**, radius 50%, `--teal-gradient`, glow `0 0 60px rgba(0,191,165,0.5)`, inset highlight. Check icon 56 black centred.
- "You're all set" 40 / 200 / -1 / line-height 1 heading + description 14 secondary 1.5 line-height.
- Get started button — primary, **50 px high** (larger than Lang/Wifi), padding 40 h, 15 px font, `marginTop: 40`.
- Version "Marathon OS · 4.2.1 (Avior)" 12 tertiary, `marginTop: 18`.

---

# Section 5 · Settings (`screens-apps-1.jsx`)

## 23 · SettingsApp (`screens-apps-1.jsx:25`)

**Layout.** TopBar "Settings" + search + avatar-circle (28 × 28 `--elev-3`). Content `padding: 14, height: calc(100% - 88px)`. No TabBar. Single scrollable column.

**Hero — Profile Card** `elev={2}`: 52 × 52 monogram circle gradient `linear-gradient(135deg, #1a4a3e, #0a0a0b)` with `--teal-border` border, "AR" 18 px teal-bright. Text: "Avery Rhodes" 16 / 600 + "avery@marathon.id · Cloud, Sync" 12 secondary. Chevron right.

**Four sections.** Each `SectionLabel` + `Card` with rows.
- **Marathon Intelligence** — rows with `rgba(0,191,165,0.18)` icon backgrounds (subtle teal tint). "Marathon Intelligence (On, 3.2 GB model)" / "Focus (Sleep until 7 AM)" / "Wallet & Passkeys (12 sites)".
- **Connectivity** — Wi-Fi (Mesh-5G), Bluetooth (On), Airplane, Hotspot (Off).
- **Device** — Display, Sounds, Notifications (42), Privacy (3 apps).
- **System** — Storage (38.4 GB / 128 GB), Battery, About (Marathon OS 4.2.1 / Avior).

**Reused.** TopBar, Card, Row, SectionLabel.

---

## 24 · SettingsDisplay (`screens-apps-1.jsx:81`)

**Layout.** TopBar "Display" + back. Content padding 14. No TabBar. Layout: appearance row (Dark / no light theme note) → brightness slider → display-scale picker (3 mini-phone tiles) → accent picker (5 teal swatches).

**Brightness slider.** Hero. 6 px height track `--w-08`, teal-gradient fill 62%, 18 px circular thumb teal-bright with white border + `boxShadow: 0 0 12px var(--teal-glow)`. Value "62" 11 / 600 tabular at top right.

**Display-scale picker.** 3-col grid gap 8. Each tile: 65% aspect-ratio mini-phone with nested mini text (fonts 5/7/9 px scaling to demo). Label "Small / Default / Large" 13 + sublabel "0.9× / 1.0× / 1.2×" 11. Active (Default): `1px --teal` border + `0 0 0 1px --teal-border, inset 0 1px 0 --w-06`.

**Accent picker.** Row: "Marathon Teal" label + 5 swatches 22 × 22 circles `[#006b5d, #00897b, #00bfa5, #1de9b6, #5dffdc]`. Active (#00bfa5) has 2 px white border.

**Novel.** **MScalePicker** (mini-phone tile preview). **MAccentSwatches** primitive.

---

# Section 6 · Communication (`screens-apps-1.jsx`)

## 25 · PhoneDialer (`screens-apps-1.jsx:171`)

**Layout.** TopBar "Phone" + search + more. Content flex column padding 24 h, `calc(100% - 88px - 70px)`. TabBar (Dial active).

**Hero — number display.** Min-height 110 centred. "(415) 555-0142" 36 / 200 / 1 px tracking primary + "Devon Park · Mobile" 14 / 500 / teal-bright below.

**Keypad.** 3 × 4 grid gap 14. Each **key 68 × 68 circle**:
- `--elev-2` bg, `1px --w-04` border, radius 50%
- Double shadow: `inset 0 1px 0 var(--w-06), 0 4px 12px -6px rgba(0,0,0,0.6)`
- 24 / 300 digit + optional 9 px / secondary / 1.5 tracking letter code ("ABC" etc.).

**Controls row.** Flex justify-space-around. Left user-icon 22 px tertiary + **centre call button 64 × 64 circle teal-gradient with phone icon 28 px black + glow `0 0 24px rgba(0,191,165,0.5), inset 0 1px 0 rgba(255,255,255,0.3)`** + right x-close 22 px tertiary.

**Novel.** **MDialerKey** (68px circle with optional letter code). **MCallActionRow** centred-button-with-flankers.

---

## 26 · MessagesList (`screens-apps-1.jsx:234`)

**Layout.** TopBar "Messages" + search + **teal compose square button**. Content `padding: 6 12 0, height: calc(100% - 88px - 70px)`. TabBar with **3 tabs: Pinned / All (active) / Archive**.

**Thread rows.** No Card wrap — raw `.m-row` flex row gap 14, padding 14 v + 12 h.
- **44 × 44 avatar circle**, per-contact tint (`#3a6b9c`, `--teal-bright`, `#a85968`, etc.). "Black: true" flag changes monogram text colour. 1 px `--w-08` border. Monogram 15 / 600.
- Content: name row (15 px / 600 if unread, 500 if read, justify between) + timestamp 11 secondary (teal-bright if unread). Subtitle: snippet truncated.
- **Unread badge**: pill `padding: 0 7, --teal-bright bg, black text, 11 / 700, 4 px radius`.

**Data.** 8 threads — Maya Chen (2 unread), Marathon Devs, Mom, Linear, Devon, Studio B, Alex, Spam likely.

---

## 27 · MessagesThread (`screens-apps-1.jsx:295`)

**Layout.** Custom 88 px **glass header** (no TopBar): `--glass-titlebar` + `blur(12px)` + border-bottom. Padding `0 14 12`. Layout: back chevron 24 + **36 × 36 avatar `#3a6b9c`** + name/status flex 1 + phone icon 20 + more icon 22 secondary.

**Conversation area** `top: 116, bottom: 70` flex column gap 12 padding `0 14`.

**`ThreadBubble`.** Align-self end/start, max-width 78%.
- **Sent (me, not composing)**: teal-gradient bg, black text, glow `0 0 12px rgba(0,191,165,0.2)`. Status text below right: "✓ DELIVERED" or "✓✓ READ" 10 / secondary.
- **Received**: `--elev-2` bg, primary text, no glow.
- Padding `8 12`, radius 4, `1px --w-04` border (or teal for composing), 14 / 1.35.

**Composer bottom bar** 70 px: `--glass-tabbar` + `blur(14px)`. Flex row: plus button 36 × 36 `--elev-2` + input field 38 × 36 `--bb10-surface` "iMessage" + send button 36 × 36 teal-gradient circle with send icon 16 black.

**Conversation.** Maya: "Are we still on for 8?" / Me: "Yes — heading out in a sec." [read] / Them: "Cool, I saved a spot near the back" / Them: "There's a soundcheck before, you'll like it" / Me: "Even better. Want me to grab drinks on the way?" [delivered] / Them: "Yes please, the usual".

**Novel.** **MThreadHeader** (glass header with avatar + typing indicator). **MBubble** (variants for sent/received + status indicators). **MComposer** bar.

---

## 28 · MailInbox (`screens-apps-1.jsx:391`)

**Layout.** TopBar "Inbox" + search + more. Content `top: 116, bottom: 70`. Inner header: "2 unread · 84 total" left + "Sort: Newest" teal right. Mail rows below. **4-tab TabBar** (Inbox / Starred / Sent / All).

**Mail row.** Flex row gap 14 padding `14 14`. **Unread signals (three layers)**:
1. **Left bar**: 3 px wide full-height `--teal-bright`
2. **Background tint**: `rgba(0,191,165,0.025)` (2.5%)
3. **Sender name**: 14 / 700 primary (vs. 500 if read)

Avatar: **36 × 36 square** rounded 4 (not circle — formality vs. messages), tint per sender. Initials 13 / 600 white. Right column: name + timestamp top row, subject (13 / 600 unread else 400) `marginTop: 2`, preview (12 secondary) `marginTop: 3`.

**Data shown.** Linear "MARS-204 assigned" [unread], Cassandra Reyes "Re: Q4 retro" [unread], GitHub PR, Stripe invoice, Curlybrace Slate Notes 2.4, Maya "concert lineup pdf".

**Novel.** **MMailUnreadBar** treatment (3-layer signal is mail-specific).

---

# Section 7 · Web & Store (`screens-apps-1.jsx`)

## 29 · BrowserApp (`screens-apps-1.jsx:450`)

**Layout.** **No TopBar** — custom 56 px URL bar (`--glass-titlebar`) instead. Flex row: back/forward chevrons + address bar 36 px `--bb10-surface` rounded 4 + refresh + more. Page content `top: 28 + 56 = 84, bottom: 86`. Bottom 70 px toolbar (`--glass-tabbar`), 5 icons share/star/plus/tabs/profile, no labels. Tabs icon has **teal "3" badge** top-right (10 / 700 / 4 px padding / 14 px min-width).

**URL bar.** **Lock icon 12 px teal-bright** + "marathon-os.dev" 13 primary + "/docs" 13 secondary.

**Page content (Marathon docs mock).** "MARATHON DOCS · v4.2" pill badge with info icon. "Building for Marathon" 26 / 200 heading + description. **Three numbered steps cards**: "01" / "02" / "03" (11 / teal-bright monospace) + title 14 / 600 + description 12 secondary + chevron. **Code block** `1px --teal-border, rgba(0,191,165,0.07)` bg, monospace 11 teal-bright: `$ marathon init my-app → Scaffolded my-app in 1.2s`.

**Novel.** **MURLBar** (custom glass header). **MStepCard** (numbered).

---

## 30 · StoreDiscover (`screens-apps-1.jsx:554`)

**Layout.** TopBar "Store" + search + avatar circle. Content `top: 116, bottom: 70`. **Featured hero card** (custom gradient) → "Trending now" rail → "Updates available · 3" Card list. TabBar (Discover active).

**Hero — Featured card.** Gradient `linear-gradient(135deg, #1a4a3e 0%, #040404 70%)`. Top-right **radial glow `radial-gradient(circle, rgba(0,191,165,0.35), transparent 60%)` at offset -40/-30**. "EDITORS' PICK" pill + "Slate Editor — for writing that doesn't fight back." 22 / 500 / -0.3 / line-height 1.15 + "Curlybrace Labs · Free with in-app pro tier" 13 secondary. Two buttons: "Get" primary 38 + "Preview" ghost 38.

**Trending rail.** Horizontal scroll gap 10 padding `0 16`. Each card 140 wide flex-shrink 0: 1:1 icon (38 px glyph), name 13 / 600, "category · ★ rating" 11 secondary. 3 apps: Lattice (teal check), Sigil (shield dark), Tide (music dark teal).

**Updates list.** Card with 3 m-rows: app + size + change-note + **inline 32 px / 12 px primary "Update" button**. Browser 24.6 MB, Slate Notes 8.2 MB, Voice Memos 4.1 MB.

---

# Section 8 · Media & Capture (`screens-apps-2.jsx`)

## 31 · MusicNowPlaying (`screens-apps-2.jsx:9`)

**Layout.** No TopBar, no TabBar. Immersive full-screen. Title row (chevron-down 22 + "PLAYING FROM · Modular Tides · Slate, 2025" caps + more icon). Album-art occupies most of upper half. Info + scrubber + controls stacked below. **Device cast strip** near bottom.

**Hero — album art.** Large square 1:1 (~280–300 px wide depending on padding). Nested gradient background, **repeating-linear-gradient vertical scan-lines masked radially** for stripe pattern (very subtle in render — low opacity). Centred glowing **tilde "~" symbol ~60–70 px teal** (smaller in proportion than the source's `90 px` constant suggests visually). Shadow `0 24px 60px -20px ... inset 0 1px 0 highlight`.

**Scrubber.** Track 4 px tall, 42% filled teal-gradient + glow. **Circular handle white-bordered at 42%**. Times "1:48" / "4:14" 11 px tabular secondary.

**Controls (centred row, gap 32).** refresh 20 secondary (outline arrows) → 50 × 50 skip-back circle → **~80–90 px play/pause circle teal-gradient + substantial teal halo extending well beyond the circle + white border** (visually larger than the source's `74 × 74` constant suggests; the glow makes it the dominant focal point) → 50 × 50 skip-forward → heart 22 teal-outline (not filled).

**Device cast strip** (full-width card, padding 14, `--elev-2` bg, 1 px border). Layout: **cast icon = concentric-arc broadcasting glyph (teal-bright)**, NOT a generic chevron + "Living Room" 14/600 + "Sonos · 2 speakers" 11/secondary below + chevron-right far right.

**Novel.** **MAlbumArt** with abstract tilde + scan-mask pattern. **MMusicScrubber** with halo'd handle. **MMediaControls** with primary play button.

---

## 32 · CameraApp (`screens-apps-2.jsx:139`)

**Layout.** Solid black, no TopBar. StatusBar. **Viewfinder zone** approx `top: 90, bottom: 180` — fake landscape scene (sky-to-ground gradient, brown ground tones), 1 px white-12 grid lines at 33.33% intervals, 80 × 80 radial sun glare (`blur(20px)`). **Teal focus reticle** at 52% top × 38% left: 60 × 60 square with crosshairs, glowing box-shadow.

**Top bar** absolute `top: 32`. Flash button (34 × 34 circle dark-semi-transparent) left + "HDR · ON" 11 caps badge centre + settings cog (34 × 34) right.

**Mode picker** `bottom: 200`. Tabs: `[SLO-MO, VIDEO, PHOTO active, PORTRAIT, PANO]`. Active gets teal-bright underline. 11 / 600 / 22 px horizontal gap.

**Shutter row** `bottom: 80`. Left: **52 × 52 rounded-square gallery thumbnail**. Centre: **80 × 80 white circle shutter + 4 px black ring inside + double 3 px white outer ring**. Right: 52 × 52 rotate circle semi-transparent.

**Novel.** **MCameraViewfinder** with grid + reticle + sun-glare. **MShutterButton** double-ring primitive.

---

## 33 · GalleryApp (`screens-apps-2.jsx:718`)

**Layout.** TopBar "Gallery" + search + more. Content `top: 116, bottom: 70`. Three sections: Today · Studio B (3-col grid 3 tiles), Yesterday · Brooklyn (3-col 6 tiles), Memories (**asymmetric 2 fr 1 fr** with 2:1 hero + 1:1 tile). TabBar (Albums / Photos / Memories / Search).

**Tiles.** All 1:1 aspect (Memories left is 2:1). **Gradient backgrounds, NO actual images** — abstract "moments" view. Pattern: teal-dark, light gray, cyan-radial. Border `1px --w-04`.

**One tile has video badge**: "0:14" 9 / white in dark-semi-transparent overlay top-right.

**Memories tile** has overlaid text bottom-left: "One year ago" 14 / 600 + "14 photos · 2 videos" 11 secondary.

**Novel.** Asymmetric 2-fr / 1-fr grid for Memories. Abstract gradient-only tile pattern.

---

# Section 9 · Utilities (`screens-apps-2.jsx`)

## 34 · CalendarApp (`screens-apps-2.jsx:253`)

**Layout.** TopBar "December" + search + teal plus. Content `top: 116, bottom: 70`. Year/nav row → day headers (M T W T F S S 10 caps secondary) → 35-cell month grid → events Card below. TabBar (Day / Month / Year / Search).

**Year/nav row.** "2025" left + chevron-left + "Today" teal button + chevron-right.

**Calendar grid.** 7-col CSS grid, 1px gap, aspect 1/1.1. Cells: `--bb10-black` background, 13 px digit. **Today (5)** uses **teal-gradient background + black text + event dots**. Event-bearing days show small **4 × 4 teal dots** stacked.

**Events list Card.** 3 rows: time (right-aligned 50 px fixed, tabular) + **3 px teal vertical accent bar** + title 14 + tag 10 (design / 1:1 / personal).

**Data.** Today Dec 5 — 12:00 Design review, 15:30 1:1 Devon, 19:30 Concert · Bowery. Other dotted days 8, 11 (×2), 16, 19, 22, 24 (×3), 31.

**Novel.** **MMonthGrid** with today-highlight + event dots. **MEventRow** with left teal bar.

---

## 35 · ClockApp (`screens-apps-2.jsx:634`)

**Layout.** TopBar "Clock" + plus + more. Content `top: 116, bottom: 70`. Large analog clock SVG (max 240 px, centred). World Clocks SectionLabel + Card list. TabBar (World / Clock / Alarm / Timer).

**Hero — analog dial.** 200 × 200 SVG viewBox. Radial gradient dial (dark centre to black edge). **60 tick marks** every 6°: 12 major (`--teal-bright` 2 px) at 0/30/60/...°, 48 minor (`--text-tertiary` 1 px). Hour numbers 14 / 300 / teal-bright at 12 / 3 / 6 / 9. Hands: hour (thin white at 11:42 angle) + minute (thinner white at 8 angle) + **second (teal)**. Centre 4 px teal circle with 2 px black inner. "PM" + "FRI" markers at bottom/left 10/9 px gray.

**World Clocks Card.** 4 m-rows: offset label (left 11 secondary), city (16 / 500), time (right 22 / 200 tabular) + day. NYC local, London +5h, Tokyo +14h (Sat), Sydney +16h (Sat).

**Novel.** **MAnalogClock** SVG primitive with full tick generation.

---

## 36 · CalculatorApp (`screens-apps-2.jsx:363`)

**Layout.** AppShell. Custom 56 px glass header (Undo + "Basic" mode + menu/close). Display zone 280 px tall. Operators chip row 50 px. Keypad 5 × 4.

**Display.** Background `--bb10-deep`. Flex-end column. Expression "1,248 × 7" 18 px monospace secondary. "= 8,736" 14 teal monospace. **Big result "8,736" 52 / 200 / -1 / tabular / `--teal-bright`** right-aligned.

**Operators chip row.** Horizontal scroll, 8 chips (C, (), mod, π, √, x², sin, cos). Each `--elev-2` + inset shadow + 6 px padding + radius 4.

**Keypad.** 5 rows × 4 cols, gap 8. Buttons:
- **Equals**: teal-gradient + black text + 16 px glow shadow
- **Operators (+, −, ×, ÷)**: `--elev-3` + teal text
- **Utility (AC, +/-, %)**: `--elev-3` + teal text
- **Numbers**: `--elev-2` + primary text
All 22 / 700 weight.

**Novel.** **MCalcDisplay** triple-row layout. **MCalcKeyVariants** (number/operator/utility/equals).

---

## 37 · MapsApp (`screens-apps-2.jsx:472`)

**Layout.** AppShell. SVG map fills the screen `#0a1814` background. StatusBar. **Search card** `top: 40, left/right: 14` glass-titlebar pill. Recenter button floating `right: 14, top: 200` (42 × 42). **Bottom card** `bottom: 24, left/right: 14` with destination info + 4-action cell row.

**SVG map.** Stylised dark topology: East River (navy `linearGradient` path, dashed centreline), Bryant Park (muted green region), major roads (14 px dark + dashed accent), minor roads (6 px). Text labels (water teal-blue 9 px, park muted-green, streets tertiary).

**"You are here" marker** `top: 52%, left: 38%`: blue dot + white border + **teal glow halo**.

**Destination pin** `top: 32%, left: 68%`: SVG teardrop 34 × 44, teal fill, dark circle base, 1.5 px white stroke.

**Search card.** Search icon + "Studio B" 14 / 500 + "475 W 26th St · 0.4 mi · 7 min walk" 12 secondary + 28 × 28 avatar.

**Bottom card.** 56 × 56 thumbnail with teal gradient + map_pin icon + "Studio B" 14 / 500 + open-status 11 secondary + chips "★ 4.7" "$$" + 4 `ActionCell`s in equal-width row: **Directions / Call / Share / Save**. The **first cell ("Directions") is the *primary action* variant** — icon AND label both `--teal-bright`; the other three keep primary-text colour. The `MActionCellRow` primitive needs an `accent` slot for the leading cell, not a static all-teal or all-neutral row.

**Novel.** **MMapSVG** primitive with dual-stroke roads. **MLocationDot** + **MDestinationPin**.

---

## 38 · NotesApp (`screens-apps-2.jsx:793`)

**Layout.** AppShell. TopBar "Notes" + search + teal plus. Content `top: 116, bottom: 70`. Two sections: Pinned + Today. TabBar (Notes / Folders / Recent / Search).

**Pinned card.** Special: `SectionLabel` "Pinned" + teal star icon 12 px. Content shows **full preview**: ★-prefixed teal "MARATHON OS — DESIGN AUDIT" 11 / 600 / 0.5 spacing eyebrow + 3-line excerpt 13 / 1.5 / primary + "edited 11:14 AM · 1,294 words" 11 secondary metadata.

**Today Card.** 5 m-rows. Each: row-icon (note icon in `--elev-3` square) + title 14 + description 11 secondary + **right-aligned tag 10 / 600 / teal-bright with # prefix** (#personal, #work, #read, #home).

**Data.** Notes: Concert prep, 1:1 Devon agenda, Slate Editor release notes, Reading list, Grocery list.

---

# Wallpapers (39 – 51)

Already documented in `ANALYSIS.md §7`. Summary: 13 SVG wallpapers, all 390 × 844, palette-locked teal + neutrals. Shared `<Horizon opacity sun />` primitive at `y = HORIZON_Y = 540` (golden ratio). Slate Aurora is default. Others: Long Run (concentric arcs), Track (running lanes), Mesh (engineering grid), Contour (concentric ellipses), Stride (diagonal hairlines), Striae (density horizontals), Halftone (radial dots), Pulse (radar rings), Dawn (sunrise gradient), Tundra (cool sky), Carbon (minimal streak), Indigo Dusk (radial + stars).

---

# Novel components — consolidated list for catalog work

Aggregated from all screens. Things that need to be built that don't exist today (or are sufficiently new to warrant a dedicated component file):

**Bars / chrome.**
- `MStatusBar` redesign (28 px glass, tabular nums); `MStatusBarLock` variant (lock icon centred, no time)
- `MTopBar` 96 px large-title with glass + backdrop blur 18
- `MTabBar` 70 px with teal-gradient indicator + glow
- `MDock` — used on Frames / Switcher / QuickSettings / app surfaces. Phone-icon · inbox · **`MFrameDockIndicator`** · dim-dots · camera. The centre indicator has THREE states: numbered-circle (home mode page N), filled-square (switcher mode), and a transitional state when held.
- `MLockShortcuts` — DIFFERENT primitive used on lock screens. Just phone teal lower-left + camera dim lower-right + HomeIndicator. No centre, no dots.
- `MNowBar` 36 px live-activity strip — variants: music (5-bar visualiser), call (pulse ring + end button), nav (icon + distance), timer (countdown), pulse-only

**Active Frames (unified).**
- `MFramesView` — the 2 × 2 grid container with paged scroll. `mode` prop: `"home"` (curated widgets, with greeting block above and pinned dock below) or `"switcher"` (snapshots, no greeting, no pinned dock). Shared frame component, shared gestures.
- `MActiveFrame` — single frame, fixed 158 height, glass. Slots: `widget` (curated, header-at-top) and `preview` (snapshot, title-bar-at-bottom). Apps register both; the frame picks based on the view's mode.
- `MFrameDockIndicator` — page-number-in-circle / switcher-active-square / dim-dots states
- `HealthRings` SVG widget (Move rose / Exercise teal / Stand blue concentric arcs)

**AI surfaces.**
- `MSearchField` (Spotlight prefix with Marathon mark + cursor + halo)
- `MAIAnswer` (gradient panel + Marathon Intelligence eyebrow + body + sources row)
- `MCitationBadge` (16 × 16 teal numbered box)
- `MSourceRef` (numbered + icon + name)
- `MAIBubble` (user/AI variants)
- `MSuggestCard` (icon + title + description tile)
- `MAIActionRow` (primary+secondary chip row)
- `MMicInput` (pill + send circle)

**Lock + call.**
- `MHaloedDisplay` (teal radial halo behind any text — used for clock, calc readout, etc.)
- `MCallerAvatar` (with pulse rings)
- `MCallButton` (primary teal-gradient / decline red, 72 × 72 rotated phone)
- `MBiometricSensor` (84 × 84 circle + SVG fingerprint + halo + 6-bar progress)

**System / overlays.**
- `MHUD` (transient floating glass card — volume / brightness)
- `MKeyboard` (prediction row + 4 letter rows + send button)
- `MBubble` (chat bubble with status + composing cursor)
- `MThreadHeader` (glass header with avatar + typing indicator)
- `MComposer` bar
- `MURLBar` (glass top bar with lock + domain + path)
- `MStepCard` (numbered docs step)

**Settings / app primitives.**
- `MScalePicker` (mini-phone tile preview)
- `MAccentSwatches` (5 swatch row)
- `MModeHeroCard` (tinted gradient + glow-circle pattern)
- `MStackedCardPile` (absolute-offset card stack)
- `MVerifiedBadge` (pill)
- `MScoreRing` (concentric SVG progress)

**Lists.**
- `MHubRow` (avatar + name/time / account / snippet with unread dot)
- `MFilterChipRow` (pill chips with active variant)
- `MMailUnreadBar` (3-layer signal — left bar + tint + bold)
- `MEventRow` (time + teal accent bar + title + tag)

**Phone / dialer.**
- `MDialerKey` (68 px circle with optional letter code)

**Browser.**
- `MURLBar` (already listed above)
- `MTabsBadge` (numbered teal pill on tabs icon)

**Music.**
- `MAlbumArt` (square with scan-line overlay / abstract pattern)
- `MMusicScrubber` (halo'd handle, tabular times)
- `MMediaControls` (skip / play primary / skip)
- `MCircButton` (50 × 50 circle, primary/secondary)

**Camera.**
- `MCameraViewfinder` (gradient + grid + sun-glare)
- `MShutterButton` (80 × 80 white double-ring)
- `MModePicker` (underline-indicator tab strip)

**Calendar.**
- `MMonthGrid` (7-col with today-highlight + event-dots)
- `MEventRow` (covered above)

**Clock.**
- `MAnalogClock` (200 × 200 SVG dial + ticks + hands)

**Calculator.**
- `MCalcDisplay` (triple-row layout)
- `MCalcKey` variants

**Maps.**
- `MMapSVG` (dual-stroke roads, water + park regions)
- `MLocationDot` (blue + white + teal halo)
- `MDestinationPin` (teardrop SVG)
- `MActionCell` (4-cell row primitive)

**Notes.**
- `MTaggedRow` (m-row + right-aligned teal tag)

**Tasks switcher.**
- `MTaskCard` (custom — title bar at *bottom*, custom content above) — distinct from current TaskCard.qml in the shell

**Quick settings.**
- `MQSTile` (split-bay tile — left teal bay when on, right label/sub)
- `MQSSlider` (halo'd thumb)
- `MPageBar` (active = teal bar 18 × 4, inactive = circle dot)

---

# Patterns to internalise

Across all 38 screens, a small number of patterns recur as the Marathon visual signature. These are the "if you do it wrong it'll look wrong" things:

1. **Light-weight large headings.** Weight 200 for any heading ≥ 24 px. Title sizes: 84 (Display lock clock), 76 (LockMedia clock), 40 (OOBE finish heading), 36 (OOBE step headings, AppDrawer screen heading), 34 (TopBar Title 1), 28 (Title 2), 22 (Title 3).

2. **Halo around hero text.** Lock clock, dialer number, calc readout: text gets a radial-gradient blurred halo behind it (`inset: -28` ish, teal at 18–22% opacity, `blur(8px)`).

3. **Teal-gradient on primary action.** Buttons / play / send / continue / accept call / featured CTA. Always the gradient `#1de9b6 → #00bfa5 (→ #00897b)` plus `0 0 24px rgba(0,191,165,0.5)` glow + inset highlight + 1 px white-15 border.

4. **Sharp 4 px radius on cards, 50% on avatars, 999 on chips/pills.** Squircle 14 ONLY for app icons. Never 12 / 16 / 18.

5. **Glass on chrome.** Status bar `blur(8)`, top bar `blur(18)`, tab bar / Hub header `blur(14–20)`, modals `blur(16)`, Now Bar `blur(20)`. Stacking glass over glass is banned — sheet snapshots the whole composited screen.

6. **Inset 1px highlight on lifted surfaces.** Every elevated thing (card, button, dialog, icon container, modal) gets `inset 0 1px 0 var(--w-06)` or `--w-08` as a top highlight — the design's primary depth cue.

7. **Tabular numerics on every numeric.** Times, percentages, durations, prices, file sizes. Set `font-feature-settings: "tnum"` always (Qt 6.7+ `font.features: { "tnum": 1 }`).

8. **Secondary-muted hues are semantic, not decorative.** Blue = water / Sleep / contact identity. Green = parks / financial-OK. Amber = camera permission / caution. Rose = mic permission / Move ring / Health. Violet = mentions / categorical. **Never use these for chrome.**

9. **Eyebrow labels are UPPERCASE 1.2–1.6 tracking 11 px / 700.** "ACTIVE NOW", "MEDIA VOLUME", "PRIORITY", "EDITORS' PICK", "INCOMING CALL · MOBILE", "MARATHON DOCS · v4.2".

10. **The horizon line at y = 540.** Wallpapers anchor a teal hairline at exactly that y. The system mostly composites over the horizon, so the wallpaper line shows through chrome gaps — content above and below the horizon weight differently.

---

**Status.** Design briefs captured for all 38 screens + 13 wallpapers. Combined with `ANALYSIS.md`, this is the full implementation reference. The novel-components list (~70 primitives) gives the catalog work; the patterns list gives the visual-language rules every component must satisfy.
