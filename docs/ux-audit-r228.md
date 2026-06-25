# Marathon Shell — r228 UX audit report (2026-06-25)

## Capture method
Driven via marathon-dev + marathon-touchctl over SSH. Each app tapped from home, 5 s settle, SIGUSR1 capture, attempted 200 px shortSwipeUp to return home.

## Capture issues (not findings, but blockers)
- Of 14 attempts, **only 4 apps captured cleanly** (Messages, Store, Calendar, Calculator).
- Phone, Mail, Browser, Clock, Maps screenshots show home — either silent launch failure or the back-home swipe failed and subsequent taps landed inside the running app.
- Music/Camera/Gallery captures show different apps (Store / Messages) — same root cause: navigation state didn't reset between launches.
- Notes file shows the task switcher.
- Settings file shows Calendar.

**Need a more robust audit harness** before this can be repeated: explicit "kill running app" between launches, or use a URI scheme to launch apps from the shell side.

## Captured app findings

### Messages
- "Messages" header title descender (lowercase 'g') clips into the content area below the header divider — H1 too large or line-height too tight in MTopBar.
- Empty-state icon (chat bubble) is undersized, mid-grey on black — reads as a stuck placeholder, not an intentional illustration.
- Bottom chrome stacks the app's own Pinned/All/Archive tab strip *plus* the shell's home-indicator row, ~220 px of vertical real estate.

### Store
- "EDITORS' PICK" hero card: the green decorative quarter-circle on the right overlaps the Get/Preview button row — Preview button crowds the inside edge of the circle.
- "Trending now" / "Top picks from across Flathub" headings — subhead is larger than the heading.
- Only 3 trending tiles render and then ~600 px wall of black to the tab bar. Missing skeleton/"see more"/scrollable hint.
- Tab bar (Discover/Apps/Installed/Account): inactive labels render at full opacity, active is greyed — visual treatment is inverted from the convention.

### Calendar
- ~640 px of blank canvas below the month grid — "THURSDAY, JUNE 25" header is shown but no event/agenda area. Needs MEmptyState ("No events today") for empty days.
- Weekday letter row (M T W T F S S) is rendered in low-contrast grey, barely legible against black.
- Chevron arrows beside "Today" are tiny (~20 px tap target) and offset asymmetrically — left chevron much closer to "Today" than the right.
- "2026" year label baseline-misaligned with "Today" — looks like two independent rows rather than a paired header.

### Calculator
- ~700 px of pure-black dead space above the result; only "0" visible at y=830 then the keypad starts. (Existing #426.)
- Scientific function strip ("mod π √ x² sin cos tan log ln ! ans") is single-line at full width with no internal padding — `mod` and `ans` touch the screen edges, no safe-area inset.
- The `√` key glyph sits noticeably lower than its sibling glyphs in the same row — vertical baseline misalignment.
- Top-left "Undo" and top-right ×/hamburger sit on a different baseline than the "Basic ▾" mode picker; the picker chevron is too small (~10 px) to be a credible tap target.

### Notes (actually captured the task switcher, not Notes itself)
- 2×2 task switcher card grid: bottom edges of card thumbnails clip the title chip ("Calcula…", "App St…") because the chip overlays the thumbnail rather than living in a separate footer.
- Close-X glyphs are 16-18 px and right at the bottom-right corner of each card — tight tap target, easily eaten by adjacent cards.
- Thumbnail capture path is inconsistent — Calendar card thumbnail crisp, Store card visibly aliased.

## Cross-app findings
1. **Header H1 weight is system-wide too heavy** — descender clipping or oversized lowercase glyphs eating into content below the divider, observed on Messages, Store, Calendar, Calculator headers. Consider dropping `MTopBar` title from current size to ~56 px or constraining baseline + line-height.
2. **Bottom region fights itself everywhere** — every app shows a per-app tab bar (~140 px) immediately above a shell-owned row with search + home-indicator + keyboard glyphs (~80 px). That's ~220 px of fixed bottom chrome on every screen, on top of any in-app FAB.
3. **Empty states are bare** — Messages and Calendar lean on small grey glyph + 2 lines of text. No illustration system, no contextual next-action hint.
4. **Inactive tab labels brighter than active** — Messages, Store, Calendar all have the same inversion. Active item identified only by the small teal underline + glow; text colour ladder is backwards.

## Tested-good (no observed issues from the Phone capture earlier this session)

### Phone
Dialer keypad clean, letter subtitles correct, big teal call button centered, tab bar (Dial/Recents/Contacts/Favorites) visible at proper proportions.

## Known-pending (not re-tested in this pass, already in PRD)
- #338 idle blanking transition
- #364 lazy sensor claim
- #366 audio refresh poll
- #412 Browser cold-start chrome-first
- #418 Maps tiles
- #421 AppLifecycleManager singleton in apps
- #425 BrowserApp focus address bar
- #426 Calculator wastes 700 px (confirmed live)
