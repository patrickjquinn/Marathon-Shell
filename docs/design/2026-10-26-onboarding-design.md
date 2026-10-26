# Onboarding

First-run setup is the first thing anyone sees of Marathon. Today it is a
tidy settings form (`shell/qml/components/MarathonOOBE.qml`): seven steps
in one template — teal heading, small teal body, a Back/Next slab — with
gestures taught by a chevron sliding back and forth across six sub-pages,
and a "You're all set" tick before a hard cut to home. This replaces it
with a short flow in which Marathon introduces itself through its own
parts, the person learns the gestures by doing them, and setup hands over
to the home screen through the gesture they will use most.

Agreed with the user from audited screenshots and two rounds of mockups
(the round-2 mockups are the reference: Keel Silica controls, Keel
ambience theming).

## Goals

- **One story, six beats**, each one screen, in this order:
  1. **Hello** — Marathon introduces itself.
  2. **Get online** — one screen, optional.
  3. **Keep it private** — the passcode, required.
  4. **Make it yours** — wallpaper; the system takes its colour from it.
  5. **Easy to read** — text and icon size on the real home grid.
  6. **Your Hub** — practise the edge swipe on the real peek.
  Then **Off you go**: setup leaves the way it began, with a flick up.
- **Real parts, not pictures.** Keel Silica controls for every control;
  the shell's own `MarathonAppGrid` for previews; the shell's own
  `MarathonPeek` for the Hub practice; the real nav bar drives the
  gestures; Keel's ambience re-themes setup live.
- **Learn by doing.** The person performs the swipe up (to begin), the
  edge swipe (Hub) and the flick up (to finish). Each practice moves on by
  itself when done. If it hasn't happened after 8 seconds or two failed
  tries, a Silica `TouchInteractionHint` demo plays; after the demo a
  quiet "Not now" appears. Nobody gets stuck.
- **Motion with meaning**, three hero moments and calm transitions
  everywhere else: the greeting over the wallpaper's glow; the new
  wallpaper opening in a circle from the tapped thumbnail as everything
  re-themes; setup shrinking away (rounded corners) under the finger as
  the home screen builds in behind it.
- **Every string translatable** (`qsTr` with translator comments), built
  on the localisation foundation (`docs/design/2026-10-26-localisation.md`).
- **Reduce motion respected**: with `reduceMotion` on, hero motions become
  cross-fades and the demo hint plays once, without looping.

## Non-goals

- Accounts, restore from backup, Android (Deckard) setup.
- Teaching back and quick settings during setup. They get one in-context
  hint each, the first time they are useful (see Beat details: After setup).
- Tall-phone-specific layouts beyond what Silica's theme scaling gives;
  layouts must fit both the 720×720 HackberryPi and 720×1440 phones.

## Anti-goals

- No pictures of UI standing in for UI.
- No dead controls: a language button only lists languages that ship
  (localisation foundation); accessibility opens settings that exist.
- No "Skip to the end": optional steps have their own "Not now"; the
  passcode cannot be skipped (there is no PAM password to fall back on).
- No setup-only gestures: everything practised works the same afterwards.

## Beat details

**Hello.** Full-bleed current wallpaper, dimmed, with a slow soft glow in
the highlight colour. "M A R A T H O N" eyebrow; a greeting in large light
type cross-fading every 2.5 s through the shipped languages' greetings
("Hello", "Hallo", "Bonjour", "Hola", "Dia dhuit"). Two Silica `Button`s:
**Accessibility** (a sheet with Reduce motion `TextSwitch` and the text
size `Slider`, both bound to the existing settings) and **Language**
(shows the current language's native name; opens a list from
`availableLanguages`, preview languages marked "Preview"). Silica
`InteractionHintLabel`: "Swipe up on the bar to begin". A swipe up on the
real nav bar pill starts setup; so do a tap on the pill and Enter, for
switch, keyboard and screen-reader users.

**Get online.** Heading "Get online", lead "So the time, weather and
updates look after themselves." Networks as Silica `ListItem`s (signal
icon, name, "Connected" in the secondary highlight colour on the joined
one, lock icon on secured ones); rescan as today; "Other network…" as
today. `SecondaryButton` "Not now" beside `Button` "Continue". Behaviour
(scan on entry, retry, password dialog) carries over from the current
page.

**Keep it private.** Heading "Keep it private", lead "Choose a passcode
for your messages, photos and accounts." Six dots; Silica `Keypad`
(no letters, no symbols) with a Silica `IconButton` delete key beside 0;
enter, then confirm, exactly as today's logic (6 digits,
`Security.setQuickPINFirstRun`). Physical keyboard digits keep working.

**Make it yours.** Heading "Make it yours", lead "Your wallpaper sets
Marathon's colours, everywhere." A framed live preview: `MarathonAppGrid`
on the chosen wallpaper, two rows, with the pill. Below, round thumbnails
of the built-in wallpapers (the existing set plus three new photographs
with clearly different accents — warm, violet, deep blue — sourced, never
generated, credited in `CREDITS`). Tapping one sets the wallpaper through
the normal settings path; the new wallpaper opens in a circle from the
tapped thumbnail (≈450 ms, OutCubic) while Keel's ambience re-themes
setup. `Button` "Continue".

**Easy to read.** Heading "Easy to read", lead "Drag until your home
screen feels right." A live `MarathonAppGrid` that re-lays-out as the
Silica `Slider` ("Text and icon size", 75–150 %, step 5, value text "N%")
changes `userScaleFactor`. `Button` "Continue".

**Your Hub.** Heading "Your Hub", lead "Messages and notifications wait
at the left edge. Swipe in to peek." The left edge is left to the real
`MarathonPeek`; on entering the beat, Marathon posts a real notification
("Welcome to Marathon" / "Swipe in from the left edge any time to see
what's new."), which stays in the Hub after setup. When the peek reaches
its icon stop or opens fully, the beat confirms ("That's it" / "Let go
part-way to glance; keep going to open it.") and moves on after 1.5 s.

**Off you go.** "You're ready" / "Flick the bar up, the way you began, to
go home." The flick on the real pill drives setup's surface with the
finger: it shrinks (to 45 %) and rises with rounded corners (the shell's
`windowcorner` shader), committing past the same threshold as minimising
an app, springing back otherwise. On commit, setup completes
(`firstRunComplete = true`, unlock as today) and the home screen's icons
build in with a 30 ms stagger.

**Progress.** A thin five-segment bar under the status bar on beats 2–6;
none on Hello and Off you go. Back is the normal back gesture (pill left)
and goes one beat back; there is no Back button.

**After setup.** Two one-time hints, each via Silica `FirstTimeUseCounter`
and `InteractionHintLabel`, shown once ever: on the first app opened, "Drag
the bar left to go back"; on the first return home, "Pull the bar down for
quick settings".

## Constraints and assets

- Keel is unmodified. Silica's `TouchInteractionHint` draws its finger
  from the theme icon `graphics-edge-swipe-arrow`, which Marathon's icon
  theme lacks: add it to `marathon-icon-theme` (an icon, drawn to the
  theme's style; not a wallpaper).
- The time step goes: 12/24-hour follows the locale, automatic time zone
  is on by default (both still in Settings).
- Credits follow `shell/resources/wallpapers/CREDITS`. Built-in accents are listed in `crates/marathon-shell-native/src/ambience.rs`
  `BUILT_IN`; the new ones get entries with their measured accents.
- Must fit 720×720 at the HackberryPi's scale and 720×1440 phones.

## Settled for the builder

- **Gestures while locked.** The session is locked for the whole of setup
  (`SessionStore.isLocked` defaults to true and setup unlocks at the end),
  and the nav bar's upward gestures and the shell's peek edge are gated
  on it. Setup does not loosen those gates. Its own `MarathonNavBar` gets
  a `setupMode` property that lets swipe up, tap and the finish drag
  through while locked; the Hub beat hosts its own `MarathonPeek` (the
  same component, the same `NotificationService`), sized to the beat.
- **The welcome notification** goes through `NotificationService.addNotification`,
  app "Marathon", so it persists into the real Hub after setup. The beat
  succeeds when that peek reaches its icon stop or opens fully.
- **Rounded shrink** uses `QtQuick.Effects` `MultiEffect` with a rounded
  rectangle mask (as `MarathonPinScreen.qml` already uses MultiEffect), not
  the `windowcorner` material, which is specific to window textures.
- **Home behind setup** is the real home screen: while `firstRunComplete`
  is false the shell's state is already "home", drawn under setup. The
  icon build-in is a one-shot entrance on the home grid triggered when
  setup completes.
- **Unlock** stays as today: `Security.setQuickPINFirstRun` on the
  passcode beat; `setupComplete` → `SessionStore.unlock()` when the finish
  commits.
- **The Keel pieces exist** in the Keel build (`TouchInteractionHint`,
  `InteractionHintLabel`, `FirstTimeUseCounter`, `Keypad`,
  `SecondaryButton`); only the hint's icon is missing.
- **Localisation first.** `availableLanguages` and `language` come from
  the localisation plan's Task 1; this work starts after it lands.
- **A failed try** is a gesture that starts where the beat expects it
  (on the pill, or within the edge strip) and is released short of the
  commit threshold. Counted per beat, reset on entering it.
- **The wallpapers** are chosen: `moos-sunset.jpg` (warm; "Foggy sunset
  view from Moos mountain", Thomas Heins, CC BY 4.0),
  `oeschinensee-night.jpg` (deep blue; "036 Milky Way during Perseids
  seen from Oeschinensee", Giles Laurent, CC BY-SA 4.0) and
  `sylvester-dawn.jpg` (violet; "Lake Sylvester during the sunrise,
  Kahurangi", Michal Klajban, CC BY-SA 4.0), scaled to a 2400 px height
  (the night sky to 1440 px wide), re-encoded.

## Left to the builder

Exact durations and easing beyond the ones named; how the beats are
structured in files (one component per beat is expected); how the nav
bar's gesture progress is surfaced to drive the finish.
