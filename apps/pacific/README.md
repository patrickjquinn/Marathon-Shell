<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: Apache-2.0
-->

# Pacific

Pacific is Marathon's web browser, on WPE WebKit. It began as Shipwright's browser for Sailfish OS and came into Marathon from Shipwright 7a6c40a8 as a core app; the Sailfish packaging (rpm/), the Sailfish engine build (engine/) and the prestart unit stayed behind.

## Licence

Pacific's own code is Apache-2.0, Marathon's licence. The web view (`webview/`) is LGPL-2.1-or-later, as the Atlantic view it was ported from, and the page bridges in `webview/js/` taken from Atlantic and Jolla are MPL-2.0. `LICENSES/` has the three texts; each file's SPDX header says which applies. The bundled third-party data keeps its own licences (below).

| Path | What |
| --- | --- |
| `core/` | `pacific-core`, its own Cargo workspace: profile database, frecency and suggestions, search engines, sessions, tab lifecycle, content blocking, autoconsent, HTTPS-first, reader mode, downloads, site settings, privacy, Shoal Keys client, Pilot helpers. `core/data/versions.env` pins the bundled third-party data. |
| `app/` | `shipwright-pacific`, its own Cargo workspace: the `Pacific` singleton (`bridge.rs`), the models `TabModel`, `SuggestionModel`, `PacificList` (`models.rs` declares them; `tabs.rs`, `suggestions.rs`, `lists.rs` implement them), the core thread (`worker.rs`), HTTPS for suggestions and list updates (`net.rs`), `openUrl` on D-Bus (`dbus.rs`). |
| `ui/qml/` | The pages, components, cover and Keel Actions (`actions/PacificActions.qml`). |
| `ui/tests/` | QML tests (`run-tests.sh`), lint (`lint.sh`, `qmllint-accepted.txt`) and `mockview/`, a stand-in for `Shipwright.Pacific.WebView` with the same API that draws pages from fixtures (a small C++ base for the properties whose change signals QML cannot declare, plus QML). |
| `webview/` | `Shipwright.Pacific.WebView 1.0`: the Qt 6 view of WPE WebKit pages, the agent API for Pilot, pacific-minibrowser. |
| `icons/` | The app icon. |

## Engine and web view

The engine is the `wpewebkit` aport (`packaging/packages/wpewebkit`): WPE WebKit 2.54 on the legacy libwpe + WPEBackend-fdo API, with Atlantic's and Pacific's patches. Frames reach Qt's scene graph as EGLImages bound to GL textures, with no CPU copy. Qt Quick has to run on the OpenGL RHI. `webview/README.md` has the QML API for the UI and the core: WebView, WebProfile, WebEngine and the request types; the keyboard and input method; the agent API (isolated script world, element snapshots, trusted taps, headless views); building and running.

Atlantic (SpecSierra's atlantic-engine and atlantic-browser) did the hard part: the WebKit build, the Qt 5 view this one is ported from, and months of device measurements cited throughout; the view's files credit them in each header.

## Browser: core, app and UI

### Threads

Nothing slow runs on the GUI thread. The profile databases, the session file, the filter lists and the compiled filter engine belong to one core thread (`worker.rs`); invokables queue jobs to it and results come back as signals through `CxxQtThread::queue`. Network requests (search suggestions, filter-list updates) run on a two-thread tokio runtime. What answers at once is in memory: what typed text means (`classify`), HTTPS-first steps, the discard policy, Pilot snapshot checks. Models change rows in place (`dataChanged`), so a title or progress update never recreates a web view.

### Profile and ranking

One SQLite file (`~/.local/share/org.shipwright/pacific/places.db`, WAL) holds places and visits with an FTS5 index over titles and URLs, bookmarks in folders, adaptive input history, site settings, downloads, search engines, HTTPS exceptions and the daily protection counts. Private tabs use an in-memory database of the same shape, gone at exit.

The address bar ranks pages with Firefox's exponential-decay frecency (`core/src/frecency.rs` documents it): each of a page's ten newest visits adds its weight (typed 200, bookmark or top site 100, link 50, reload or restore 20) times `2^(-age/30 days)`, scaled by total visits over sampled visits and doubled for bookmarks; the score is stored as the date it decays to 1, so ordering never needs recomputing. Suggestions add topicality to that (host prefix, host, path and title-word matches, typed before, bookmarked, and Firefox-style input history; `suggest.rs`), put the typed address or search first, offer "switch to tab", complete the most frecent host inline, and append the engine's suggestions only when allowed (not in private tabs, not for addresses or text with `@` or long digit runs). DuckDuckGo is the default engine; eight more are built in, keywords (`w sailfish`) search one once, and custom engines take a `%s` template.

### Sessions and tab lifecycle

The normal tabs (never the private ones) are saved as `session.lz4` (LZ4 JSON, atomic, the previous copy kept as a backup) two seconds after a change and when the app goes to the background, with WebKit's own session state per tab (back/forward list) and a coarse scroll position. A `running` marker tells a crash from a clean exit; the restore policy is always, after a crash, or never. Recently closed tabs (ten) can be reopened.

The live-tab budget comes from `/proc/meminfo`: 5 web processes on 7 GiB or more (the 8 and 12 GB Jolla Phones), 3 from 3.5 GiB, else 2; moderate pressure (`MemAvailable` under 15% or 600 MiB) halves it and critical pressure (8% or 300 MiB) keeps only the tab in front. Least recently used background tabs are discarded first (`WebView.discard()`, after a thumbnail); the tab in front, audible tabs, tabs with a form being edited and tabs used in the last 30 s never are, pinned tabs only under critical pressure. A discarded tab reloads when shown. Hidden-page timer throttling and animation suspension are on.

### Protection

- **Blocking.** Brave's `adblock` crate (MPL-2.0, unmodified) compiles the enabled lists (EasyList, EasyPrivacy, uBlock filters and privacy, Peter Lowe's; annoyances, social and cookie lists optional). Network rules reach the engine as WebKit content-blocker JSON converted by the same crate (`blocker/webkit.rs`, 50,000 rules per filter, compiled once by WebKit into a DFA shared by every WebProcess, so blocking costs no memory per tab); converted again only when the lists or the sites with blocking off change. Each filter's JSON is kept, and `filters.json` records a filter as compiled only once the engine's store has confirmed it (`core/src/blocker/record.rs`): at every start, filters never confirmed (a run killed during the first compile) or that the store cannot load are compiled again from that JSON. While a wanted filter is not in force the shield shows a warning and the site and privacy pages say protection is incomplete. Turning blocking off disables the filters (`WebProfile.disableContentFilter`; they stay in the engine's store and `enableContentFilter` brings them back), and the page in front reloads so the change shows at once; a site's exception reloads the page once its filters are compiled again. Generic element hiding (`##.ad`, about 13,700 selectors in the default lists) is the engine's too: `webkit.rs` gathers it from all the lists into its own filter, the selectors joined 250 to a `css-display-none` rule as Safari blockers do, with `site#@#` exceptions as `unless-domain`, and `$generichide` sites and the allow list ending the filter with `ignore-previous-rules`; nothing runs in the page for it. (The crate's own hiding rules are left out of the lists' filters: they sit before its closing rule for first-party documents, which voids them in WebKit.) Site-specific hiding, procedural filters and scriptlets from Brave's `adblock-resources` are injected per page by the core. The engine is also cached as `engine.dat`, the crate's own serialisation, with the allow list in `allowlist.json`, for a WebProcess extension if one is added. Lists ship in the package (blocking works offline from the first start) and refresh every four days with conditional requests. On the host, the five default lists give 113,473 content-blocker rules in 8 filters (12.1 MB of JSON, 43.5 MB in the engine's store), converted in 2.2 s (debug build, off the GUI thread) and compiled by WebKit in 3.6–4.0 s.
- **Cookie banners.** DuckDuckGo's autoconsent (MPL-2.0) standalone build, pinned by version and SHA-256 and checked before use, runs in each page and answers consent dialogs with "reject all"; it reports to its own script message handler (`shipConsent`, patched in when the script is loaded), which feeds the per-page summary, so no page's console is forwarded to the app.
- **HTTPS first.** Every `http://` navigation is tried over HTTPS first; failure or 3 s without an answer shows an interstitial ("continue to the site" remembers the host, per profile or per private session), and an HTTPS site that redirects back to HTTP is accepted quietly. No upgrade list (DuckDuckGo's Smarter Encryption data is CC BY-NC-SA). Local hosts, IP addresses and single-label names are never upgraded.
- **Per page and per site.** The toolbar's shield counts what the engine's content filters blocked on the page (`WebView.blockedRequestCount`, reported by the web view's WebProcess extension), and the site page names the blocked hosts (counted in memory as each request is blocked; the site page hears of changes at most four times a second and the day's totals are written at most once a second, and on a page change, a tab closing and at exit); the site page turns blocking, JavaScript, desktop site and autoplay off or on for the site and answers permissions (location, camera, microphone, notifications). The privacy page shows lifetime totals.
- **Privacy.** No telemetry. Pacific's own requests are filter-list updates and, while typing and only when allowed, search suggestions. Clearing data by time range covers history, cookies and site data, cache, the download list, site settings and the session. Global Privacy Control is the engine's own (`WebProfile.globalPrivacyControl` on both profiles): `Sec-GPC: 1` on every request and `navigator.globalPrivacyControl` for scripts, following the setting.

### Spelling

Text fields are spell-checked by the engine (WebKit's enchant/hunspell checker, dictionaries from `shipwright-pacific-engine`). Settings, Spelling turns it off and chooses the languages from the installed dictionaries (`WebEngine.availableSpellCheckingLanguages`); with none chosen the engine follows the phone's language.

### Reader mode, downloads, home screen

Reader mode extracts the article from the live DOM with `dom_smoothie` (MIT; chosen over `readabilityrs` for its maintenance and releases) and writes a static page under a Content Security Policy that allows no script, frame or form, with the reading time (230 words or 500 CJK characters a minute), in light, sepia or dark. Downloads go to a free name in `~/Downloads` and are listed with progress, open, share, retry and remove. "Add to home screen" writes a launcher entry that opens the page.

### Logins from Shoal Keys

Pacific stores no passwords. Shoal Keys serves `org.shipwright.Keys.Autofill1` (bus name `org.shipwright.shoal-keys.Autofill`; shoal/keys/README.md, "Autofill for other apps"): when a page has a login form, Pacific asks Keys which logins it has for the site (names only, only while Keys is open) and offers "Sign in as …"; filling brings Keys up, where the person unlocks if needed and taps the login to send, and Pacific comes back to the front by itself when the answer arrives (or the choice is declined). When a login form is submitted, Pacific offers to save it, and Keys asks again before storing. The client is `core/src/passwords.rs`; Pacific needs the `ShoalKeysAutofill` Sailjail permission, which Keys installs. Pilot never fills passwords.

### Pilot (Keel Actions)

`ui/qml/actions/PacificActions.qml` declares the browser for Pilot and any MCP client (ADR-0018), app id `org.shipwright.pacific`:

- Opening: `browser.open`, `browser.search`.
- Tabs: `tabs.list`, `tabs.switch`, `tabs.close`; entities `tab`, `bookmark`, `history` (`keel://org.shipwright.pacific/<type>/<id>`) with find and resolve.
- Reading: `page.read` (readable text, bounded, default 8,000 characters), `page.find`, `page.links` (a snapshot outline of links, buttons and fields with ids like `e12`, and the forms with what submitting them would do), `page.screenshot`, `page.scroll`.
- Acting, always confirmed by the person: `page.click`, `page.fill` (never password, one-time-code or payment fields), `page.submit` (also destructive and outbound; payment forms refused).
- Browse for me: `browse.open` loads pages in a headless view on the private profile, without touching the person's tabs; the browser shows "Pilot is browsing" with Show (the page opens in a private tab) and Stop; `browse.show`, `browse.close`; every page action takes `background: true` for that view.
- Bookmarks and history: `bookmarks.add`, `bookmarks.find`, `history.search`, `downloads.list`.
- Context: the page in front (never a private tab), its title, address and the selected text, so "summarise this" works. A shortcut reads the page in front.
- The actions that return page content declare Keel's `untrusted` flag (keel/README.md): keel-mcp then marks their results `_meta["org.shipwright.keel/untrusted"]` and says in the text that they are data, never instructions.

Private tabs do not exist for Pilot. Page content is web data that may try to steer an assistant: it is cleaned (control, bidirectional and zero-width characters removed) and bounded by the core, returned in fields named as page content with `untrusted: true`, and the descriptions say it is data, never instructions. Element ids come from the web view's snapshot in its isolated script world, which the page cannot read or forge, and must match `^e[0-9]+$`. The setting "Let Pilot use the browser" turns all of it off. `app/tests/actions.rs` runs the declarations through Keel's generator and Reef's review and checks these promises.

### UI

Pacific follows the Sailfish Browser's chrome and Silica's patterns (page stack, Dialogs with DialogHeader for questions, ContextMenu on long press, RemorsePopup/RemorseItem before anything is deleted, ViewPlaceholder for empty lists, cover actions, Theme colours and sizes only), with everything within thumb reach:

- **Toolbar** at the bottom, as the stock browser's, 108 px at pixel ratio 1, on frosted glass (`FrostedGlass.qml`): the strip of the page behind it, captured at half resolution, blurred by MultiEffect with its colours lifted, under the theme's overlay tint; nothing is captured while the bar is off screen (flinging Wikipedia with the bar up: 90 frames a second with or without it). Silica's tab icon with the count in it (the incognito icon for private tabs); back when there is a page to go back to; the lock (a warning for an insecure page) with the count of what was blocked, which opens the site's page; the page's registrable domain (`en.wikipedia.org` shows as `wikipedia.org`; tap it for the address entry); the reader button when the page has an article, stop while loading; `icon-m-menu` for the page menu. While a page loads the highlight gradient fills the bar from the left. It slides away while scrolling down and returns on scrolling up; the page relayouts once after the slide, never every frame, and a page that moves only because the view grew does not bring it back.
- **Gestures on the bar**: sideways, the page follows the finger and the next tab slides in with its last picture, then becomes the tab in front; upwards, the page shrinks into the tab overview, which opens past a third of the way. Both are interruptible.
- **Page menu**: a DockedPanel with the stock menu's rows (new tab, new private tab; find in page, share, add to app grid, desktop version as a switch; bookmarks, history, downloads, settings) and its footer of four buttons (close the tab, forward, bookmark, reload). Zoom for a site is a slider on the site's page.
- **Tab view**: Silica's tab bar (tabs, private, with their counts) over one column of cards on a phone in portrait (more when wide), as in the stock browser: site icon, title and close button over the page's last picture. Swipe a card sideways to close it, press and hold for its context menu (pin, duplicate, close others, close); pinned tabs come first; a search field filters the tabs. The stock tab toolbar below: back to the page, a new tab, and a menu with new tabs, reopening the last closed tab and closing all (with remorse).
- **Address page**: the field under the thumb with the list growing upwards. Before typing: paste and go (or paste and search), recent searches, the most visited sites. While typing: the address or search first, inline completion of the most frecent host, history and bookmarks with site icons, switch to tab, earlier searches, the engine's suggestions; each row can be put into the field to edit.
- **New-tab page**, anchored to the bottom: the most visited sites by their short names, recent searches (list items; press and hold to remove), the newest bookmarks and the privacy report. Private tabs explain plainly what private means.
- **A site's questions** (a permission, with "remember for this site"; saving a login in Shoal Keys) are Dialogs pushed over the page, as the stock browser asks them. Notes that need no answer (a login Shoal Keys could fill, Pilot browsing) sit above the toolbar on the same glass. Full panels cover the HTTPS interstitial, certificate errors, failed loads and crashed pages; the long-press menu on links, images and misspelt words fades in over the page.
- **Site icons**: fetched once over HTTPS into the cache (never for private tabs); until then each site has its initial on a colour of its own.
- Pacific is the default browser through its desktop file (`x-scheme-handler/http(s)`, `text/html`) and `org.shipwright.pacific.ui` `openUrl(as)` on the session bus (`app/src/dbus.rs`).
- Touch targets are at least `Theme.itemSizeSmall`; text uses Theme font sizes (they follow the system text size); untrusted text is shown as plain text.

**Start-up.** `PACIFIC_TRACE_STARTUP=1` prints the time from the process's start to the first frame. On the host (debug build, offscreen software rendering, the mock web view, a profile in use) it is about 180–200 ms over 7 runs, the same with the page menu, the link menu and Pilot's actions built eagerly or (as now) after the first frame. The phone, with booster-keel and the real engine, still has to be measured.

### How Pacific compares

A self-review against Chrome for Android and Safari for iOS (from their 2025–2026 releases as documented in the research notes; not re-checked against the latest builds), screen by screen with the screenshots from `tools/screenshots/run.sh --only pacific`:

| Screen | Better than both | Where Pacific still trails |
| --- | --- | --- |
| Toolbar | Bottom by default (Chrome defaults to the top), the stock Sailfish layout; blocked count and connection state in one tap target | No long-press shortcuts on the bar yet |
| Switching tabs | Live peek while swiping the bar, as Safari; Chrome has no peek on its bottom bar | No momentum across several tabs in one fling |
| Tab overview | The stock Sailfish tab view with search; close button in the card's header, never over the picture | No tab groups (Chrome and Safari have them); private tabs show no pictures (by design, nothing written to disk), Safari blurs them instead |
| Address bar | Recent searches and paste-and-go without typing; suggestions next to the thumb; nothing sent to the engine for addresses, e-mail-like or number-like text, or in private tabs | No on-device search of page text yet |
| Protection | Ads, trackers and cookie banners handled by default (Chrome does neither; Safari only hides IP from trackers); HTTPS first with an honest interstitial; a privacy report on the new-tab page | No per-site tracker list detail beyond blocked hosts and counts |
| New tab | One-handed layout from the bottom | No customisation of the shortcuts beyond "remove" (history) |
| Reader | Locked-down reader page (no script) with reading time, three themes | No text-to-speech or translation |
| Logins | Keys asks per fill and names the site; nothing stored in the browser | Autofill depends on Shoal Keys being installed; no passkeys (engine has no WebAuthn) |
| Pilot | Pages read in a private background tab the person can see and take over; every click, fill and submit confirmed | Needs the real engine to prove on real sites |

Fixed during the reviews: the address was cut by icons; titles in the tab overview were truncated; the close button sat on the picture; tabs opened behind had no picture for the peek. In the native-design pass, a pill-shaped address field, a segmented private switch, the page's colour on the toolbar, an icon-grid menu, recent-search chips and prompts docked as bars gave way to the stock browser's toolbar, menu and tab view, Silica's tab bar, list items and Dialogs.

### Building and checking

```
# core
cd shoal/pacific/core && cargo clippy --all-targets -- -D warnings && cargo test
# app (needs Qt 6 and Keel's sailfishapp; see tools/keel-launcher)
cd shoal/pacific/app && cargo clippy --all-targets -- -D warnings && cargo test
# QML tests and lint
KEEL_QML=build/keel/qml shoal/pacific/ui/tests/run-tests.sh
KEEL_BUILD=build/keel shoal/pacific/ui/tests/lint.sh
# screenshots (real module, mock web view)
KEEL_QML=build/keel/qml tools/screenshots/run.sh --only pacific --out /tmp/shots
# screenshots on the real engine (a host build of webview/ and its prefix, see
# webview/README.md "Running on the host"): local fixture sites, no internet;
# pacific-real/checks.txt says no blocked request reached the server and the
# article was sent with Sec-GPC: 1
PACIFIC_ENGINE_PREFIX=<prefix> PACIFIC_ENGINE_BUILD=<webview build> KEEL_QML=build/keel/qml \
    tools/screenshots/run.sh --only pacific-real --out /tmp/shots
# the package (prebuild.sh first)
tools/build/native/native.sh shoal/pacific/rpm/shipwright-pacific.spec
```

Real-file tests run when the data is around: `PACIFIC_EASYLIST`, `PACIFIC_RESOURCES_JSON` and `PACIFIC_AUTOCONSENT_JS` point at a list, Brave's resources and the autoconsent build (`rpm/data/` after `prebuild.sh`). `PACIFIC_OFFLINE=1` stops the app's own requests.

### Needs the engine or the phone

- Everything the mock web view only imitates: real loads, the HTTPS-first timings, content filters compiling and blocking, cosmetic injection and scriptlets on real pages, autoconsent on real consent dialogs, reader extraction from real DOMs, thumbnails, discard and reload, session-state restore, downloads, the agent API on real pages.
- Memory: the live-tab budget and pressure thresholds against measured PSS on the 8 and 12 GB phones; content-filter compile time and peak memory with 139,000 rules.
- The blocked-request count per page: the UI listens for `WebView.blockedRequest(url)` (the engine agent is adding it; the mock emits it), `Sec-GPC`.
- Lipstick: `openUrl` for a running instance, D-Bus activation through Sailjail, the default-browser choice, the Keel Actions service under Sailjail with the launcher script.
- Shoal Keys autofill under Sailjail: Keys owning `org.shipwright.shoal-keys.Autofill`, D-Bus activation through `sailjail -p`, and Keys coming to the front for a fill.
- Start-up time with booster-keel and the real engine; 60 fps of the swipe and overview gestures with live WebKit textures.
