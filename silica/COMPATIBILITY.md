<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# Keel Sailfish.Silica compatibility

Status of every public `Sailfish.Silica` 1.0 type (names from the public
Silica documentation and the keel-compat catalogue) in Keel 0.1, for
`tools/keel-compat/src/catalog.rs`.

- **implemented**: the documented API (properties, defaults, methods,
  signals, enums) is present and covered by the tests in `tests/`.
- **partial**: importable and usable, with the gaps noted.
- **missing**: not provided; an app using it fails to load that file.

Since 2026-10-01 the components are Silica's own BSD QML of Sailfish OS
5.2.0.15 (sailfishsilica-qt5 1.2.156) ported to Qt 6, on Keel's clean-room
native types (keel/silica/PROVENANCE.md). Pixel-level comparison with Silica
on a device (tier C) has not been done (see keel/README.md, "Needs device
verification").

## Module

| Item | Status | Notes |
| --- | --- | --- |
| `import Sailfish.Silica 1.0` | implemented | Qt6 QML module in the Qt6 import path; imports `Keel 1.0`. |
| `import Keel 1.0` | implemented | Keel extensions: `Ambience`, `Shell` (keel-shell client). |
| `image://theme/...` | partial | Provider installed per engine; loads Sailfish theme icons from the device theme directories. No icons ship with Keel, so on a desktop they are missing (logged). Icons the theme has only as colour scheme variants (`icon-m-file-pdf-dark`/`-light`, ...) resolve to the ambience's variant; a few icons some themes lack fall back to a substitute (`icon-l-video` to `icon-m-video`, file type icons to the generic document icon); `?mono=<color>` recolours monochrome icons only. |
| `Sailfish.Silica.private` | missing | Not supported for apps. Keel has a module of this name for Silica's own (BSD) QML: clean-room native types and Silica's private BSD QML (keel/silica/PROVENANCE.md); other private names are absent and its API may change. keel-compat keeps reporting it as missing. |
| `import Sailfish.Silica.Background 1.0` | partial | `ColorBackground` and `Corners` only (Keel's stand-ins). |
| `import Sailfish.Share 1.0` | implemented | `ShareAction` (`mimeType`, `resources`, `title`, `selectedTransferMethodInfo`, `trigger()`, `toConfiguration()`, `loadConfiguration()`, `done`) opens the system share dialog (`org.sailfishos.share`, Qt 5, out of process) as Silica apps do; without that service (hosts) `trigger()` copies the shared links and text to the clipboard. `ShareProvider` (`method`, `registerName`, `capabilities`, `triggered`) and `ShareResource` make the app a share target (`/share/<method>` on the session bus, as declared with `X-Share-Methods` in its desktop entry). Not run on a device yet. |

## Platform modules

The Sailfish and Nemo platform modules apps import next to Silica, as
keel-compat catalogues them (`MODULES` in tools/keel-compat/src/catalog.rs;
a test keeps the two in step). Statuses as for types: **implemented** (the
documented API, tested), **partial** (gaps noted), **missing**. Details:
keel/nemo-compat/PROVENANCE.md and keel/platform/README.md.

| Module | Status | Notes |
| --- | --- | --- |
| Nemo.DBus | implemented | keel/nemo-compat (upstream plugin, Qt 6 fixes). |
| Nemo.Notifications | implemented | keel/nemo-compat (upstream plugin). |
| Nemo.KeepAlive | implemented | keel/nemo-compat (upstream plugin; libiphb on the device). |
| Nemo.Configuration | implemented | keel/nemo-compat (upstream plugin; dconf through mlite-qt6 on the device). |
| Nemo.Ngf | implemented | keel/nemo-compat: libngf-qt's plugin; events played by ngfd. |
| Nemo.Policy | implemented | keel/nemo-compat: nemo-qml-plugin-policy on libresourceqt's ResourceSet (Qt 6), Keel's QtDBus engine for the resource policy manager; grants locally when no manager runs. |
| Nemo.Thumbnailer | implemented | keel/platform: nemo-qml-plugin-thumbnailer built for Qt 6 (Thumbnail, image://nemoThumbnail); videos and PDFs through thumbnaild. |
| Nemo.Mce | implemented | keel/platform: libmce-qt built for Qt 6 (display, tklock, battery, charger, cable, power save, call state). |
| org.nemomobile.dbus | implemented | Legacy URI of Nemo.DBus. |
| org.nemomobile.notifications | implemented | Legacy URI of Nemo.Notifications. |
| org.nemomobile.keepalive | implemented | Legacy URI of Nemo.KeepAlive. |
| org.nemomobile.configuration | implemented | Legacy URI of Nemo.Configuration. |
| org.nemomobile.ngf | implemented | Legacy URI of Nemo.Ngf. |
| org.nemomobile.policy | implemented | Legacy URI of Nemo.Policy. |
| org.nemomobile.lipstick | implemented | keel/nemo-compat: lipstick's launcher types built for Qt 6 (LauncherItem, LauncherModel, LauncherWatcherModel, LauncherFolderModel, LauncherFolderItem; launched through GIO). The home screen's own types (compositor, windows, notification list, volume) run in Lipstick's process and are not for apps. |
| org.nemomobile.accounts | implemented | keel/platform: nemo-qml-plugin-accounts on libaccounts-qt6 (system accounts database). |
| org.nemomobile.mpris | implemented | keel/platform: qtmpris built for Qt 6 (MprisPlayer, MprisManager, Mpris). |
| Sailfish.Share | implemented | keel/silica: ShareAction opens the system share dialog (org.sailfishos.share), clipboard fallback without it; ShareProvider/ShareResource receive shares. |
| Sailfish.Media | implemented | keel/platform: every documented member of MediaKey (Lipstick GRABBED_KEYS), MediaPlayerControls, MetadataReader, MediaListItem, MediaPlayerControlsPanel, MediaPlayerPanelBackground, and MprisPlayerControls (its API as Jolla's lock screen uses it, over Amber.Mpris). |
| Sailfish.Pickers | implemented | keel/platform: all 16 documented pages and dialogs; Tracker 3, else a file system scan. |
| Sailfish.WebView | implemented | keel/platform: every member of the WebView documentation (stable, additional and experimental attributes) on Qt WebEngine (Chum qt6-qtwebengine), else a placeholder that opens pages in the browser; pages scaled by WebEngineSettings.pixelRatio; the page's dialogs, permission requests, context menu, downloads and file and colour pickers through sailfish-components-webview's own Popups, Pickers and Controls (MPL-2.0), popupProvider honoured; frame scripts and the message manager in an isolated JavaScript world; `security` from Keel's own TLS check of the page's server; `crashed`, selection, input focus, scroll geometry and chrome gesture from Qt WebEngine. The Gecko engine itself is not there: frame scripts get Gecko's message-manager globals but no XPCOM (`Components`, `docShell`). |
| Sailfish.WebEngine | implemented | keel/platform: WebEngine (observers: the app's own topics plus Gecko's `clipboard:setdata`, `final-ui-startup`, site permissions and downloads; user style sheets; `isAccelerated`/`setIsAccelerated` as Chromium's GPU switch, read at Qt WebEngine's start; `runEmbedding`, `stopEmbedding`, `notifyFirstUIInitialized`, `lastWindowDestroyed`, `contextDestroyed`), DownloadHelper, and WebEngineSettings applied to Qt WebEngine (JavaScript, images, popups, user agent, downloads, CORS preferences, pixelRatio; cookieBehavior, doNotTrack and colorScheme through Keel.WebEngine, package -webview-qtwebengine); Gecko preferences without a Chromium counterpart are kept without effect. |
| Sailfish.WebView.Popups | implemented | keel/platform: sailfish-components-webview's popups (MPL-2.0) for Qt WebEngine's JavaScript dialogs, sign-in, location and camera/microphone permissions (remembered) and link/image context menu; PopupProvider. |
| Sailfish.WebView.Pickers | implemented | keel/platform: sailfish-components-webview's pickers (MPL-2.0) for file uploads (Sailfish.Pickers) and colours. |
| Sailfish.WebView.Controls | implemented | keel/platform: sailfish-components-webview's controls (MPL-2.0): PermissionModel, PermissionFilterProxyModel and PermissionManager over the remembered site permissions; TextSelectionController inert (Chromium draws its own selection). |
| Sailfish.Secrets | implemented | keel/platform: sailfish-secrets' plugin built for Qt 6, talking to sailfishsecretsd. |
| Sailfish.Crypto | implemented | keel/platform: sailfish-secrets' plugin built for Qt 6, talking to sailfishsecretsd. |
| Sailfish.Accounts | implemented | keel/platform: sailfish-components-accounts (BSD) built for Qt 6 with libsignon-qt and libbuteosyncfw; sign-in through signond, sync profiles for msyncd. |
| Sailfish.Policy | implemented | keel/platform: PolicyValue and the AccessPolicy singleton (and libsailfishpolicy-qt6) reading the policies MDM applications set (/var/lib/policy/policy.conf) and the privacy switch; read only and fail-closed (unknown is reported as disabled). |
| Amber.Mpris | implemented | keel/platform: amber-mpris built for Qt 6 (MprisPlayer, MprisController, Mpris, MprisMetaData); or Chum's amber-qml-plugin-mpris-qt6. |
| Amber.Web.Authorization | implemented | keel/platform: amber-web-authorization built for Qt 6 (OAuth1, OAuth2Ac, OAuth2AcPkce, OAuth2Implicit, RedirectListener); sign-in opens in the browser. |

Counts: 31 implemented, 0 partial, 0 missing of the 31 module rows above.

Enum holders that are not rows of their own: `Formatter` (with Format), `Dock` (DockedPanel, Drawer), `DateTime` (TimePicker), `FocusBehavior` (TextField, TextArea), `OpacityRamp` (OpacityRampEffect). Names from the public Silica documentation and API listing; numeric values are Keel's own except `Formatter`'s, which follow the listing.

## Types

| Type | Status | Notes |
| --- | --- | --- |
| AddAnimation | implemented | Silica's BSD QML (1.2.156). |
| ApplicationWindow | implemented | Cover in a second top-level window per keel/shell/PROTOCOL.md; orientation from keel-shell; `_defaultPageOrientations`; `bottomMargin`; `background` group partial (color, image). The window's own children share `contentItem` with the page stack, as in Silica (a child with a negative `z`, such as a camera viewfinder, is under the pages). |
| BackgroundItem | implemented | Silica's BSD QML (1.2.156). |
| BusyIndicator | implemented | Silica's BSD QML (1.2.156). |
| BusyIndicatorSize | implemented | |
| BusyLabel | implemented | Silica's BSD QML (1.2.156). |
| Button | implemented | Silica's BSD QML (1.2.156). |
| ButtonLayout | implemented | C++ item with attached `ButtonLayout.newLine`; unset spacings default to `Theme.paddingMedium`, `preferredWidth` to `Theme.buttonWidthSmall` (Keel's choice). |
| Clipboard | implemented | C++ singleton (`hasText`, `text`). |
| ColorPicker | implemented | Silica's BSD QML (1.2.156). |
| ColorPickerDialog | implemented | Silica's BSD QML (1.2.156). |
| ColorPickerPage | implemented | Silica's BSD QML (1.2.156). |
| ColumnView | implemented | Silica's BSD QML (1.2.156). |
| ComboBox | implemented | Silica's BSD QML (1.2.156). |
| ContextMenu | implemented | Silica's BSD QML (1.2.156). The dimming-free layer is a compiled Qt 6 shader; on the software scene graph (no shaders) the window above and below the menu's item is shaded instead. |
| Cover | implemented | `status` follows keel-shell's (or Lipstick's, direct mode) cover exposure, through `Activating` and `Deactivating` (one event-loop turn each); `size` is `Cover.Small` when the compositor gives the cover window a small cover's size, else `Cover.Large`. |
| CoverAction | implemented | Triggered by taps on the cover window, which keel-shell forwards. |
| CoverActionList | implemented | `iconBackground`, `enabled`; `window` accepted but unused. |
| CoverBackground | implemented | Silica's BSD QML (1.2.156). |
| CoverPlaceholder | implemented | Silica's BSD QML (1.2.156). `icon.source` resolves against the app's file (bare absolute paths become `file://`), not Keel's `qrc:`; same for `icon` of Button, IconButton, Switch, IconTextSwitch. |
| CutoutMode | implemented | Enum only. `Screen.topCutout` and the corners come from the adaptation's dconf (`/desktop/sailfish/silica/cutouts`, `rounded_corners`), as on Sailfish OS. |
| DatePicker | implemented | Silica's BSD QML (1.2.156); week numbers from Keel's native `Util.weekNumberList`. |
| DatePickerDialog | implemented | Silica's BSD QML (1.2.156). |
| DetailItem | implemented | Silica's BSD QML (1.2.156). |
| Dialog | implemented | Silica's BSD QML (1.2.156). |
| DialogHeader | implemented | Silica's BSD QML (1.2.156). |
| DialogResult | implemented | |
| DialogStatus | implemented | |
| DockedPanel | implemented | Silica's BSD QML (1.2.156), with its BSD PanelBackground; `modal`, `animationDuration`, `background`. `Dock` enum holder. |
| Drawer | implemented | Silica's BSD QML (1.2.156). `Dock` enum holder. |
| EnterKey | implemented | Attached (`enabled`, `highlighted`, `iconSource`, `text`, `clicked`); exposes an `enterKeyType` hint for the input method. |
| ExpandingSection | implemented | Silica's BSD QML (1.2.156). |
| ExpandingSectionGroup | implemented | Silica's BSD QML (1.2.156). |
| FadeAnimation | implemented | Silica's BSD QML (1.2.156). |
| FadeAnimator | implemented | Silica's BSD QML (1.2.156). |
| FirstTimeUseCounter | implemented | Silica's BSD QML (1.2.156); persists through `Nemo.Configuration` (keel/nemo-compat). |
| Format | implemented | C++ singleton with the `Formatter` enum holder (FormatType, ArticleType, TextFormatType; names and values from the public API listing). `formatDate`, `formatDuration`, `formatFileSize`, `formatArticle`, `formatText`; English strings and layouts are Keel's own (QLocale). |
| GlassItem | implemented | Native item in the private module (`plugin/cpp/private/glassitem.h`, clean-room); `qml/GlassItem.qml` exports it from `Sailfish.Silica` as Silica does. |
| GridItem | implemented | Silica's BSD QML (1.2.156); the remorse container under the item is Keel's stand-in (Silica's is not open). |
| HighlightImage | implemented | Silica's BSD QML (1.2.156). In a light ambience an untinted monochrome theme icon is drawn in the palette's primary colour (Keel's HighlightImageBase), as Sailfish's theme does. |
| HorizontalScrollDecorator | implemented | Silica's BSD QML (1.2.156). |
| Icon | implemented | Silica's BSD QML (1.2.156). |
| IconButton | implemented | Silica's BSD QML (1.2.156). |
| IconTextSwitch | implemented | Silica's BSD QML (1.2.156). |
| InfoLabel | implemented | Silica's BSD QML (1.2.156). |
| InteractionHintLabel | implemented | Silica's BSD QML (1.2.156). |
| Keypad | implemented | Silica's BSD QML (1.2.156). |
| Label | implemented | Silica's BSD QML (1.2.156), default `textFormat` from the window's `_defaultLabelFormat`. `TruncationMode.Fade` fades through Silica's OpacityRampEffect shader (compiled for Qt 6; tested with OpenGL under Xvfb); the software scene graph, which runs no shaders, elides instead. `palette` colours come from Keel's own derivation formulas, to be compared with Silica on a device. |
| LinkedLabel | implemented | Silica's BSD QML (1.2.156) on Keel's `LinkParser` (Rust): URLs, email addresses and phone numbers; default action `Qt.openUrlExternally()`. |
| ListItem | implemented | Silica's BSD QML (1.2.156): menu (`showMenuOnPressAndHold`, alias `openMenuOnPressAndHold`), remorse (`remorseAction`, `remorseDelete`), `hidden` animations. |
| MenuItem | implemented | Silica's BSD QML (1.2.156). |
| MenuLabel | implemented | Silica's BSD QML (1.2.156). |
| Notice | implemented | Clean-room QML (`text`, `duration` with `Notice.Short`/`Long`, `anchor` flags `Center`/`Left`/`Right`/`Top`/`Bottom`, offsets, `show()`, `dismiss()`); numeric values are Keel's. Shown through `Notices`. |
| Notices | implemented | Clean-room QML singleton: `show(text, duration, anchor, horizontalOffset, verticalOffset)` queues notices, shown one at a time for their duration as Silica's BSD `NoticeItem` in the window's indicator layer; a tap dismisses. |
| OpacityRampEffect | implemented | Silica's BSD QML (1.2.156); drawn by a compiled Qt 6 shader (not on the software scene graph, where the source is shown unfaded). |
| Orientation | implemented | |
| Page | implemented | Silica's BSD QML (1.2.156) on Keel's `SilicaMouseArea` stand-in. |
| PageBusyIndicator | implemented | Silica's BSD QML (1.2.156). |
| PageHeader | implemented | Silica's BSD QML (1.2.156). |
| PageNavigation | implemented | |
| PageStack | implemented | Silica's BSD QML (1.2.156) (with `PageStack.js`) on Keel's native gesture area: push/pop/replace/replaceAbove/pushAttached/popAttached/navigateForward/navigateBack/clear/find/nextPage/previousPage, `busy`, `depth`, `currentPage`. As in Silica, a push or pop while a transition runs is refused with a warning. On headless platforms (offscreen, minimal) animated operations complete at once unless `KEEL_PAGE_TRANSITIONS=1`. |
| PageStackAction | implemented | |
| PageStatus | implemented | |
| PagedView | implemented | Keel's own (clean room, Silica's is native): every documented member and attached property, plus `PagedView.isCurrentItem` and `PagedView.exposed` that Silica's BSD TabView/TabItem read; drags with thresholds and flicks, the four wrap modes, the four directions, alignment, spacing, the page cache; a model and delegate, or an ObjectModel of the app's own items (their `visible` stays the app's). |
| Palette | implemented | `palette` on SilicaItem, SilicaControl, Label and the controls (Keel's native palette: inherited colours, `colorScheme`, derived highlight colours), and the `Palette` type for an app's own palettes. A Palette the app declares is a subtype of the items' palette type, so an item's `palette` goes into a `QtObject` or `var` property, not a `Palette` one. |
| PasswordField | implemented | Silica's BSD QML (1.2.156). |
| ProgressBar | implemented | Silica's BSD QML (1.2.156). |
| ProgressCircle | implemented | Silica's BSD QML (1.2.156) with its BSD ProgressCircleBase; the ring is a compiled Qt 6 shader (not drawn on the software scene graph). |
| PullDownMenu | implemented | Silica's BSD QML (1.2.156). |
| PushUpMenu | implemented | Silica's BSD QML (1.2.156). |
| Remorse | implemented | Silica's BSD QML (1.2.156). |
| RemorseItem | implemented | Silica's BSD QML (1.2.156). |
| RemorsePopup | implemented | Silica's BSD QML (1.2.156). |
| RemoveAnimation | implemented | Silica's BSD QML (1.2.156). |
| Screen | implemented | C++ singleton (`width`, `height`, `widthRatio`, `sizeCategory`, `topCutout`, `hasCutouts`, the corners (cutouts and corners from the adaptation's dconf through libdconf; `KEEL_SCREEN_CUTOUTS`/`KEEL_SCREEN_ROUNDED_CORNERS` override), `Screen.Small`..`ExtraLarge`), plus Qt Quick's Screen members (`pixelDensity`, `devicePixelRatio`, `orientation`, `primaryOrientation`, `desktopAvailableWidth`/`Height`, `name`, ...; primary screen). Which import an unqualified type name resolves to depends on the Qt version: the first import in the file that has it up to Qt 6.8 (checked on Qt 6.4.2; Qt 6.8.3's import code orders the same way, not run here), the last from Qt 6.10 (checked on Qt 6.11.2). So on Qt 6.4-6.8 `Screen` is Qt Quick's attached Screen when QtQuick or QtQuick.Window is imported before Sailfish.Silica, and on 6.10+ when it is imported after. Under `import QtQuick 2.0`..`2.14` keel/qt5compat's shims re-export Keel.SilicaScreen after Qt Quick, so `Screen` is Silica's in either order (as in Qt 5, whose Qt Quick 2.x had no Screen); Qt 6 code (`import QtQuick` unversioned, 2.15, 6.x) writes `S.Screen` for Silica-only members (`import Sailfish.Silica 1.0 as S`; importing Sailfish.Silica first also gives Silica's `Screen`, but lets Qt Quick's names win over Silica's components); keel-compat flags the cases left. |
| ScrollDecorator | implemented | Silica's BSD QML (1.2.156). |
| SearchField | implemented | Silica's BSD QML (1.2.156). |
| SectionHeader | implemented | Silica's BSD QML (1.2.156). |
| Separator | implemented | Silica's BSD QML (1.2.156). |
| SilicaControl | implemented | Keel's stand-in for the native type: `highlighted`, `palette`. |
| SilicaFlickable | implemented | Silica's BSD QML (1.2.156). |
| SilicaGridView | implemented | Silica's BSD QML (1.2.156). |
| SilicaItem | implemented | Keel's stand-in for the native type: `highlighted`, `palette`. |
| SilicaListView | implemented | Silica's BSD QML (1.2.156). |
| SilicaWebView | implemented | Gone from Silica's current documentation (it was QtWebKit's WebView with Silica's pulley menus and header). Keel's own on Keel's Sailfish.WebView: Silica's members (pulley menus, header, quick scroll, page navigation lock) and QtWebKit's WebView API (load status and navigation requests with their enums, `experimental` userAgent, preferences, evaluateJavaScript, postMessage/messageReceived through `navigator.qt`); the page scrolls inside the web engine, so the view's own Flickable members do not follow the page, and pulley menus open at the page's ends. Needs shipwright-keel-platform-webview. |
| SlideshowView | implemented | Silica's BSD QML (1.2.156). |
| Slider | implemented | Silica's BSD QML (1.2.156). |
| StandardPaths | implemented | C++ singleton over `QStandardPaths` writable locations. |
| Switch | implemented | Silica's BSD QML (1.2.156). |
| TapInteractionHint | implemented | Silica's BSD QML (1.2.156). |
| TextArea | implemented | Silica's BSD QML (1.2.156) (TextBase); `textTopMargin`, `focusOutBehavior` (`FocusBehavior` enum). |
| TextField | implemented | Silica's BSD QML (1.2.156) (TextBase): label, placeholder, writable `acceptableInput`, `errorHighlight`, EnterKey, `labelVisible`, `textTopMargin`, `focusOutBehavior`. |
| TextSwitch | implemented | Silica's BSD QML (1.2.156). |
| Theme | implemented | Full documented singleton API (colours, fonts, font sizes, paddings, item/icon/button/cover sizes, opacities, flick physics, `pixelRatio`, `horizontalPageMargin`, `colorScheme`, `rgba()`, `highlightText()`, `highlightFromColor()` and friends, `iconForMimeType()`, `presenceColor()`, `dp()`). Colours come from the ambience keel-shell forwards (`KEEL_AMBIENCE_*`, `AmbienceChanged`); sizes are base values times `pixelRatio`. |
| TimePicker | implemented | Silica's BSD QML (1.2.156): the dial ring is a compiled Qt 6 shader, the hand indicators Keel's stand-in `TimePickerGlassItem` on the native `GlassItem`. `DateTime` enum holder for `hourMode`. |
| TimePickerDialog | implemented | Silica's BSD QML (1.2.156); the clock in the middle is Keel's stand-in `ClockItem` (Silica's is not open). |
| TouchBlocker | implemented | |
| TouchInteraction | implemented | Enum holder (`Left`, `Up`, `Right`, `Down`, `Swipe`, `EdgeSwipe`, `Pull`); numeric values are Keel's. |
| TouchInteractionHint | implemented | Silica's BSD QML (1.2.156); uses the `icon-m-gesture` theme icon. |
| TruncationMode | implemented | See Label for Fade. |
| ValueButton | implemented | Silica's BSD QML (1.2.156). |
| VerticalScrollDecorator | implemented | Silica's BSD QML (1.2.156). |
| ViewPlaceholder | implemented | Silica's BSD QML (1.2.156). |

Counts: 103 implemented, 0 partial, 0 missing of the 103 rows above
(module rows excluded).

## Behaviour notes

- **Pages from URLs** are created with ApplicationWindow as their context
  parent, so page files see `pageStack`, `app` ids and properties from the
  main QML file as in Silica.
- **Pulley menus** are Silica's BSD PulleyMenuBase on Keel's native
  `PulleyMenuLogic`: they open on drag past the threshold and select the
  item under the highlight on release.
- **Shaders**: Silica's QML draws pulley menus, context menus, opacity ramps,
  progress circles and the time picker ring with `ShaderEffect`s; Keel ships
  them as compiled Qt 6 shaders (`qml/shaders/`). The software scene graph
  (offscreen tests) runs no shaders, so there the layers are skipped and
  ramps are not faded; on the device (OpenGL ES) they are drawn.
- **Headless page transitions**: with `QT_QPA_PLATFORM=offscreen` or
  `minimal`, an animated push, pop or replace completes at once (no
  animation, `busy` stays false), so test harnesses that poll for the new
  page do not wait for a transition. `KEEL_PAGE_TRANSITIONS=1` keeps the
  animations, `KEEL_PAGE_TRANSITIONS=0` drops them anywhere.
- **Theme without keel-shell**: dark ambience defaults, `pixelRatio` 1.0
  (desktop). Override for development with `KEEL_THEME_<PROPERTY>` (for
  example `KEEL_THEME_PIXEL_RATIO=2`).
