<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# keel/platform provenance

Where every Keel platform module comes from. Open upstream code is built for
Qt 6 rather than rewritten (docs/plan.md, "Licensing and provenance");
proprietary Sailfish modules are clean-room: only the names of their public
documentation, and of public usage in the open-source corpus apps, are used,
never their code (none of it is open). "Keel's own" marks modules whose
upstream is open but cannot be built for Qt 6 (Sailfish.WebView is Gecko),
and Keel internals.

| Module | Kind | Source of the API | Code |
| --- | --- | --- | --- |
| `Sailfish.Media 1.0` | clean room | sailfishos.org/develop/docs/sailfish-media/ (type list; MediaKey, MediaListItem, MediaPlayerControlsPanel, MetadataReader pages); `onPressed`, `onReleased`, `onRepeat` as foilauth, yubikey and hutspot use them; `MprisPlayerControls` as Jolla's lock screen uses it (below) | Keel's (`media/`, `common/`) |
| `Sailfish.Pickers 1.0` | clean room | sailfishos.org/develop/docs/sailfish-components-pickers/ (all picker pages and dialogs: properties, documented defaults and the selectedContentProperties members) | Keel's (`pickers/`) |
| `Sailfish.WebView 1.0`, `Sailfish.WebEngine 1.0` | Keel's own | sailfishos.org/develop/docs/sailfish-components-webview/ (WebView, WebViewPage, WebViewFlickable, WebEngine, WebEngineSettings pages) and the same documentation in github.com/sailfishos/sailfish-components-webview (MPL-2.0, tag `1.8.0` = commit `7192cd89c98da9a2355cdc0fed8cb88f5eb20ee5`: `doc/`, the additional and experimental attribute pages); the default `pixelRatio` rule from that repository's `lib/webenginesettings.cpp`; the `security` object's member names from github.com/sailfishos/qtmozembed `src/qmozsecurity.h` (MPL-2.0, names only) and its certificate details' keys from github.com/sailfishos/nemo-qml-plugin-systemsettings `src/certificatemodel.cpp` (BSD, names only) | Keel's (`webview/`, `webengine/`) |
| `Keel.WebEngine 1.0` (Keel internal) | Keel's own | Qt WebEngine's C++ API (`QQuickWebEngineProfile`, `QWebEngineCookieStore::setCookieFilter`, `QWebEngineUrlRequestInterceptor`); Chromium's `--blink-settings=preferredColorScheme` switch | Keel's (`webengine-policy/`) |
| `Sailfish.WebView.Popups 1.0`, `Sailfish.WebView.Pickers 1.0`, `Sailfish.WebView.Controls 1.0`; Sailfish.WebEngine's `DownloadHelper` | upstream | github.com/sailfishos/sailfish-components-webview, tag `1.8.0` = commit `7192cd89c98da9a2355cdc0fed8cb88f5eb20ee5` (fetched 2026-10-02): `import/popups/`, `import/pickers/`, `import/controls/`, `lib/downloadhelper.*` | MPL-2.0 (in each file; `LICENSES/MPL-2.0.txt`), in `webview/popups/`, `webview/pickers/`, `webview/controls/`, `webengine/upstream/` |
| `Sailfish.Secrets 1.0`, `Sailfish.Crypto 1.0` and their C++ libraries | upstream | github.com/sailfishos/sailfish-secrets, commit `5a8d33e2eda2fe10a64acc42912dd3bedc736495` (fetched 2026-10-01): `lib/Secrets`, `lib/Crypto`, `qml/Secrets`, `qml/Crypto` | BSD-3-Clause (`secrets/upstream-licenses/sailfish-secrets.LICENSE`) |
| `libaccounts-qt6` | upstream | gitlab.com/accounts-sso/libaccounts-qt, tag `VERSION_1.17` = commit `c8fdd05f1a1ff5886f4649d24f2ba8c5f61cfa3a` (the version Sailfish ships as libaccounts-qt5, github.com/sailfishos/libaccounts-qt5 `0b2f2c7`): `Accounts/` | LGPL-2.1-only (`accounts/upstream-licenses/libaccounts-qt.COPYING`) |
| `org.nemomobile.accounts 1.0` | upstream | github.com/sailfishos/nemo-qml-plugin-accounts, commit `677cf189abdcc6740ac14ed9eb5479d279ff9ad1`: `src/` | BSD-3-Clause (`accounts/upstream-licenses/nemo-qml-plugin-accounts.BSD`) |
| `Sailfish.Accounts 1.0` | upstream | github.com/sailfishos/sailfish-components-accounts, tag `0.4.10` = commit `2cd683f37616aefe5e66974ece63d1a5ffdfbf58` (fetched 2026-10-02; 5.2 ships 0.4.9 as sailfish-components-accounts-qt5): `src/lib/`, `src/plugin/` | BSD-3-Clause (`sailfish-accounts/upstream-licenses/`) |
| libsignon-qt (in Sailfish.Accounts) | upstream | gitlab.com/accounts-sso/signond commit `a08b05b79100bfd535100b8341df4e8bf1441802` (the commit github.com/sailfishos/libsignon pins as its `upstream` submodule; 8.61, which 5.2 ships as libsignon-qt5) with Sailfish's client patches 0005 and 0006 from that repository's `rpm/`: `lib/SignOn/`, `lib/signond/signoncommon.h` | LGPL-2.1-only (`signon/upstream-licenses/signond.COPYING`) |
| libbuteosyncfw, profile and client parts (in Sailfish.Accounts) | upstream | github.com/sailfishos/buteo-syncfw, tag `0.11.12` = commit `5d8e112be8abcad5c77fc100f2b289902685d5a1` (fetched 2026-10-02): `libbuteosyncfw/profile/`, `clientfw/`, `common/Logger.*`, `LogMacros.h`, `SyncCommonDefs.h`, `BtCommon.h` | LGPL-2.1-only (`buteosyncfw/upstream-licenses/buteo-syncfw.COPYING`) |
| `org.nemomobile.mpris 1.0` | upstream | github.com/sailfishos/qtmpris, commit `ade1b9a8ac3b77b95b81b2cccb987daa1d61386e` (fetched 2026-10-01): `src/`, `qtdbusextended/`, `declarative/` | LGPL-2.1-or-later (`mpris/upstream-licenses/qtmpris.COPYING`) |
| `Amber.Web.Authorization 1.0` | upstream | github.com/sailfishos/amber-web-authorization, commit `0f9214d5ff9ff71cd69ec1a4adb79ec08466d9d0` (fetched 2026-10-01): `lib/`, `import/` | BSD-3-Clause (`amber-web-authorization/upstream-licenses/amber-web-authorization.LICENSE`) |
| `Amber.Mpris 1.0` | upstream | github.com/sailfishos/amber-mpris, tag `1.2.10` = commit `0dc2c15104a13c16f3028cb9e73f1e4dc886f4d0` (fetched 2026-10-02): `src/`, `qtdbusextended/`, `declarative/` | LGPL-2.1 (`amber-mpris/upstream-licenses/amber-mpris.COPYING`; file headers LGPL-2.1-or-later) |
| `Nemo.Thumbnailer 1.0` | upstream | github.com/sailfishos/nemo-qml-plugin-thumbnailer, tag `1.0.12` = commit `61c53576b521d041e39c0f1d3b4090641750c0f7` (fetched 2026-10-02; the version Sailfish 5.2 ships as nemo-qml-plugin-thumbnailer-qt5 1.0.12): `src/lib/`, `src/plugin/` | BSD-3-Clause (`thumbnailer/upstream-licenses/nemo-qml-plugin-thumbnailer.LICENSE.BSD`) |
| `Sailfish.Policy 1.0`, `libsailfishpolicy-qt6` | clean room | Sailfish's `sailfish-policy` 0.4.26 packages for 5.2 (public headers, documentation, qmldir and qmltypes, file names and strings in the shipped files) and jolla-camera's use (below) | Keel's (`policy/`) |
| `Nemo.Mce 1.0` | upstream | github.com/sailfishos/libmce-qt, tag `1.5.3` = commit `a8bbbdc63a70401bf8c1fe8a2a85ee9e7644af97` (fetched 2026-10-02; the version 5.2 ships as libmce-qt5-declarative): `lib/`, `plugin/qmcedeclarativeplugin.cpp`; host builds only: github.com/sailfishos/mce-dev `include/mce/` at `01d50d9670eef183bd6d0f1e1e3656a69af3ac2d` | BSD-3-Clause (in each file; `mce/upstream-licenses/libmce-qt.LICENSE`); mce-dev LGPL-2.1-only (`mce/upstream-licenses/mce-dev.COPYING`) |

## Sailfish.Media

`MediaKey` (C++, `media/mediakey.*`): `enabled`, `key`, `pressed` from the
documentation, the `pressed()`, `released()` and `repeat()` signals from
the corpus usage. How a key reaches an app that is not focused is
Lipstick's open code (github.com/sailfishos/lipstick, LGPL,
`src/compositor/lipstickcompositorwindow.cpp`, `refreshGrabbedKeys()` and
`eventFilter()` at `af4abc1`): the compositor reads the surface's
`GRABBED_KEYS` window property, a `QStringList` of decimal Qt key codes, and
forwards those keys' presses and releases (not auto-repeats) to the
surface. Keel sets that property with
`QPlatformNativeInterface::setWindowProperty()` (the `qt_extended_surface`
generic property on Wayland, the route keel-shell uses for `CATEGORY`,
keel/shell/src/core/lipstickwindow.cpp) and as a `QWindow` dynamic property,
on every top-level window and on windows created later; an
application-wide event filter then takes the key events before items see
them. No Lipstick code is used.

`MediaPlayerControls` (enum holder; enum names from the
MediaPlayerControlsPanel page, values Keel's), `MetadataReader`
(`getTitle(url)`), `MediaListItem`, `MediaPlayerControlsPanel` and
`MediaPlayerPanelBackground` are Keel's implementations of the documented
members on Silica; their look is Keel's.

`MprisPlayerControls` is clean-room too. Its documentation page lists no
members, and the 5.2 package's `plugins.qmltypes` is dumped without
composite types (it only shows that the module depends on Amber.Mpris), so
its API is taken from its one public user, Jolla's lock screen
(lipstick-jolla-home's `lockscreen/LockItem.qml`, as copied into public
repositories such as github.com/teleshoes/sx-config): a Loader whose `item`
has `textColor`, `width`, `buttonSize`, `isPlaying`, a settable `enabled`
and the signals `playPauseRequested`, `nextRequested` and
`previousRequested`. Jolla's QML file was not read. Keel's item follows the
current player through Amber.Mpris's `MprisController`; that `enabled`
starts out true while a player is on the bus is Keel's choice, which the
lock screen's use (shown while `item.enabled`) needs.

The title tags (`common/tagreader.*`) are read with Keel's own parser,
written from the public ID3v2.3/2.4 (id3.org), Vorbis comment and FLAC
format descriptions (xiph.org).

## Sailfish.Pickers

The 16 public types (pages: Content, Document,
Download, File, Folder, Image, Music, Video; dialogs: Folder, MultiContent,
MultiDocument, MultiDownload, MultiFile, MultiImage, MultiMusic, MultiVideo)
with the documented properties and defaults. A pick sets
`selectedContent` / `selectedContentProperties` and returns to the page
below the picker, as the documented examples (and bitsailor and
sfos-forum-viewer) expect; the multi dialogs keep `selectedContent` (a
ListModel with the documented roles) current. The layout and the internal
types (`PickerPageBase`, `ContentPickerView`, ...) are Keel's. Content comes
from Tracker 3 when the indexer answers (`pickers/trackersource.*`): Keel
reimplements the client side of Tracker's D-Bus endpoint protocol from the
public description in Tracker's own sources (gitlab.gnome.org/GNOME/tinysparql
3.1.2 and 3.7.1, `src/libtracker-sparql/tracker-endpoint-dbus.c`,
`bus/tracker-bus-cursor.c`, LGPL-2.1-or-later; read for the wire format, no
code copied). Otherwise, and for downloads and file pickers, a bounded scan
of the home directory and memory cards (`pickers/filesource.*`).
Thumbnails are Qt's own image scaling.

## Sailfish.Gallery

`ThumbnailImage` and `ImageViewer` only, the two types apps outside the
Gallery app use (Shoal Messages' attachment picker, the Jolla Camera's
camera roll). Clean room: the names, properties and signals are those the
apps' own QML uses (`source`, `size`, `mimeType`, `duration`, `selected`,
`clicked`; `source`, `active`, `viewMoving`, `zoomed`, `zoomOut()`); no
Sailfish.Gallery code or QML was read. The look and behaviour are Keel's,
on Silica's `GridItem` and `SilicaFlickable`; `ImageViewer` is Shoal
Camera's own stand-in (`shoal/camera/ui/Shoal/Camera/gallery/
CameraImageViewer.qml`, Shipwright's) without its text.

## Sailfish.WebView and Sailfish.WebEngine

The documented WebView members
(`active`, `canGoBack`, `canGoForward`, `httpUserAgent`, `loadProgress`,
`loaded`, `loading`, `popupProvider`, `privateMode`, `security`, `title`,
`url`, `webViewPage`; `contentOrientationChanged`, `linkClicked`,
`loadRedirect`, `viewDestroyed`; `clearSelection`, `goBack`, `goForward`,
`load`, `loadHtml`, `loadText`, `reload`, `runJavaScript`, `stop`), the
WebEngine and WebEngineSettings singletons (members, enums, documented
defaults and the Gecko preference each setting stands for), over Qt
WebEngine's public QML API (checked against Qt 6.4's `QtWebEngine`
qmltypes with qmllint). Sailfish's implementation is Gecko (EmbedLite and
qtmozembed, Qt 5 only); none of it is used. Mapping:

| Sailfish | Keel on Qt WebEngine |
| --- | --- |
| `runJavaScript(script, cb, errCb)` (script must `return`) | the script runs as a function body; exceptions go to `errCb` |
| `privateMode` | an off-the-record `WebEngineProfile` per view |
| other views | one persistent profile (`storageName: "keel-webview"`) per app |
| `httpUserAgent`, pref `general.useragent.override` | `profile.httpUserAgent` |
| `javascriptEnabled`, pref `javascript.enabled` | `settings.javascriptEnabled` |
| `autoLoadImages`, pref `permissions.default.image` | `settings.autoLoadImages` |
| `popupEnabled`, pref `dom.disable_open_during_load` | `settings.javascriptCanOpenWindows` |
| prefs `security.disable_cors_checks`, `security.fileuri.strict_origin_policy` | `settings.localContentCanAccessRemoteUrls`, `localContentCanAccessFileUrls` |
| `downloadDir` with `useDownloadDir` | `profile.downloadPath` |
| `linkClicked`, `loadRedirect` | `navigationRequested` of type LinkClicked, Redirect |
| `pixelRatio`, pref `layout.css.devPixelsPerPx` | the view's `zoomFactor` (pixelRatio over the screen's devicePixelRatio, which is 1 in Keel apps); default as Sailfish's, below |
| `cookieBehavior`, pref `network.cookie.cookieBehavior` | Keel.WebEngine: a cookie filter on the profile's cookie store (`AcceptAll`; `BlockThirdParty` refuses cookies Qt WebEngine marks third-party; `BlockAll`) |
| `doNotTrack`, pref `privacy.donottrackheader.enabled` | Keel.WebEngine: a request interceptor adds `DNT: 1` |
| `colorScheme` | Keel.WebEngine: Chromium's preferred colour scheme (`--blink-settings=preferredColorScheme=0` dark, `1` light, in `QTWEBENGINE_CHROMIUM_FLAGS`): dark for `PrefersDarkMode`, light for `PrefersLightMode`, the ambience's for `FollowsAmbience` (LightOnDark: dark). Chromium reads it when Qt WebEngine starts (the app's first WebView), so later changes apply from the next app start |
| other prefs | kept, no effect |
| `WebEngine` observers | an in-process bus: the app's own `notifyObservers` reach its `addObserver` topics; Keel also sends Gecko's `clipboard:setdata` (a page copied or cut text: the clipboard's text and the view's private mode), `final-ui-startup` (`notifyFirstUIInitialized`), `embed:download` (`dl-start`, `dl-done`, `dl-fail`) and answers `embedui:perms` (below) and `embedui:download` (the popups' "Save link"/"Save image") |
| `addUserStyleSheet`, `removeUserStyleSheet` | the style sheets (read here when local; an `@import` otherwise) in a `<style>` element of every page, injected as a user script in Qt WebEngine's application world |
| `isAccelerated`, `setIsAccelerated` | Chromium's GPU rendering: `--disable-gpu` in `QTWEBENGINE_CHROMIUM_FLAGS`, read when Qt WebEngine starts (the app's first WebView); false also when Qt Quick renders in software |
| `runEmbedding`, `stopEmbedding`, `notifyFirstUIInitialized`, `lastWindowDestroyed`, `contextDestroyed` | Qt WebEngine starts with the first WebView and stops with the app: `runEmbedding` does nothing; `stopEmbedding` reports `contextDestroyed` once the app's WebViews are gone; `lastWindowDestroyed` when the last WebView goes |
| `addComponentManifest` | no longer in the documentation; Gecko JavaScript components, nothing to load |
| popups and `popupProvider` | sailfish-components-webview's own popups, through Keel's message bridge (below) |
| `crashed` | Chromium's render process ended abnormally (`renderProcessTerminated`); a placeholder as Sailfish's; cleared by the next load |
| `javascriptEnabled` (per view) | the view's `settings.javascriptEnabled`, with WebEngineSettings' |
| `security` | Keel's KeelSecurity (`webengine/security.*`): qtmozembed's members; the state from the URL scheme and Chromium's `certificateError`; the certificate, protocol and cipher from a TLS handshake of Keel's own with the page's host after the page has loaded (QSslSocket, the system's CA certificates). Mixed content, tracking protection and extended validation are not reported by Qt WebEngine and read false |
| frame scripts, `loadFrameScript`, `sendAsyncMessage`, `addMessageListener(s)`, `recvAsyncMessage` | Keel's bridge (below): a script in Qt WebEngine's application world (the page's DOM, an isolated JavaScript world) is the content message manager |
| `textSelectionActive`, `imeNotification`, `firstPaint`, `painted` | from the bridge's `selectionchange`, `focusin`/`focusout` listeners; `firstPaint` and `painted` at the first finished load |
| scroll geometry (`contentRect`, `contentWidth`/`Height`, `scrollableOffset`/`Size`, `resolution`, `atXBeginning` … `atYEnd`, the scroll decorators, `moving`, `dragging`) | Qt WebEngine's `scrollPosition`, `contentsSize` and `zoomFactor`; `moving` and `dragging` while the scroll position changes; `pinching` is always false (Chromium zooms inside the page) |
| `chrome`, `chromeGestureEnabled`, `chromeGestureThreshold` | the page scrolling down past the threshold hides the chrome, scrolling up as far or reaching the top shows it |
| `desktopMode` | Qt WebEngine's own user agent; otherwise that agent with `Mobile`, as Sailfish's mobile agent (per profile: the app's shared profile follows the last view that set it) |
| `viewportWidth`, `viewportHeight`, `virtualKeyboardMargin`, `orientation`, `backgroundColor` | the view's size (the viewport less the keyboard margin), the page's orientation as `Qt::ScreenOrientation`, the view's `backgroundColor` |
| `downloadsEnabled` | the context menu's save items; page downloads are refused without it, otherwise saved to WebEngineSettings' download directory |
| `canShowSelectionMarkers`, `textSelectionController`, `setInputMethodHints`, `parentId`, `uniqueId`, `newWindow`, `suspendView`, `resumeView`, `windowCloseRequested` | kept as Sailfish's (Chromium draws its own selection handles; `uniqueId` is the view's message-manager id) |

The bridge: WebEngineBackend.qml adds a user script to each view in Qt
WebEngine's application world, run at the document's creation. It gives
frame scripts Gecko's message-manager globals (`sendAsyncMessage`,
`sendSyncMessage` without an answer, `addMessageListener`,
`removeMessageListener`, `addEventListener`, `removeEventListener`,
`content`) and reports to the view with console messages that start with a
secret of the view (`javaScriptConsoleMessage`), so that the page's own
console messages cannot pass for them; the view's `sendAsyncMessage`
reaches the frame scripts through `runJavaScript` in the same world. The
frame scripts run in that world at each document's creation, and in the
page shown when they are loaded. Gecko's XPCOM (`Components`, `docShell`)
is not there.

Sailfish's own WebView (github.com/sailfishos/sailfish-components-webview,
MPL-2.0) is open source, but it is Gecko through and through (qtmozembed,
EmbedLite); none of its WebView code is in Keel. One behaviour follows it: the
default `pixelRatio` is 1.5 times Silica's `Theme.pixelRatio`, rounded to
0.5, then to a whole number where the screen would not be a whole number
of CSS pixels at 2 or more, or where the screen is 1080 pixels wide or
wider (upstream `lib/webenginesettings.cpp`, `WebEngineSettings::initialize`;
reimplemented from that description in `webengine/webengine.cpp`).

Keel.WebEngine (`webengine-policy/`, package `-webview-qtwebengine`) is
built only where Qt WebEngine's C++ API is (`Qt6WebEngineQuick`; Chum's
`qt6-qtwebengine-devel` for the device), so that `-webview` does not depend
on Qt WebEngine. WebEngineBackend.qml creates its ProfilePolicy by name and
goes on without it.

`tests/webview/fake/QtWebEngine` is a test double of Qt WebEngine's QML
module (for hosts without Qt WebEngine): the names Keel's backend uses, as
Qt 6.4's `plugins.qmltypes` declares them; no Qt WebEngine code.
`tests/webview/qtwebengine` runs the real Qt WebEngine where it is
installed.

## Sailfish.Secrets and Sailfish.Crypto

Upstream sailfish-secrets' client libraries (`secrets/lib/Secrets`,
`secrets/lib/Crypto`) and QML plugins (`secrets/qml`), built for Qt 6.
Upstream files keep their licence headers; an SPDX header (copyright lines
from the file's own notice) was added on top of each. The two QML files have
no notice; their history (2018-2022) is all Jolla's, so they carry
`2018-2022 Jolla Ltd.`. Changes, each marked "Modified by Shipwright for
Qt 6" at the change:

1. `lib/Secrets/interactionparameters.h`, `lib/Crypto/interactionparameters.h`:
   `PromptText::operator==`/`!=` call QMap's comparison, which is a free
   function in Qt 6.
2. `lib/Crypto/keypairgenerationparameters.cpp`: `QVariant` has no
   `operator<` in Qt 6; `QVariant::compare()` instead.
3. `qml/Secrets/main.cpp`, `qml/Crypto/main.cpp`:
   `QMetaType::registerComparators()` is gone (Qt 6 finds the operators);
   gadget (value) types cannot be registered under upper-case QML names in
   Qt 6, so their enums are registered under the documented name
   (`Result.Succeeded`, `CryptoManager`'s are a QObject's and unchanged) and
   the value type under the lower-case name.
4. `qml/Secrets/plugins.qmltypes`, `qml/Crypto/plugins.qmltypes`:
   regenerated from Keel's Qt 6 build with `qmlplugindump` (export revisions
   set to 256, Qt 6's encoding of 1.0); upstream's are Qt 5 dumps.

The library names carry `-qt6` (`libsailfishsecrets-qt6.so.0`,
`libsailfishcrypto-qt6.so.0`) and the headers go under
`include/sailfish-qt6/`, so they install next to Sailfish's Qt 5 ones.

Wire compatibility with the Qt 5 daemon: the D-Bus marshalling is upstream's
own code, and every type it puts on the wire (`int`, `QString`,
`QByteArray`, `QVariantMap`, `QByteArrayList`, structs) is encoded by
libdbus, not by Qt. Keys are also serialised with `QDataStream` at a fixed
`Qt_5_6` version: `tests/secrets/tst_secrets.cpp` checks that a key written
by the same upstream code built with Qt 5.15.13 reads back identically in
the Qt 6 build, and that the Qt 6 bytes (identical but for the order of the
filter-data map entries) were read back identically by the Qt 5 build
(checked on 2026-10-01). The fake daemon in that test checks each call's
D-Bus signature against the daemon's introspection data and answers with
its own marshalling.

## libaccounts-qt6 and org.nemomobile.accounts

Upstream files keep their licence headers, with an SPDX header added on
top.

nemo-qml-plugin-accounts (9 files, all for Qt 6): `QSet::fromList()`,
`QSet::toList()` and `qSort()` replaced (`accountmanagerinterface.cpp`,
`serviceinterface.cpp`, `servicetypeinterface.cpp`,
`service-account-model.cpp`); `Q_MOC_INCLUDE` for the pointer types moc
must see complete (`account-model.h`, `account-provider-model.h`,
`accountmanagerinterface.h`, `serviceaccountinterface.h`,
`service-account-model.h`). This copy builds for Qt 6 only.

libaccounts-qt: unchanged (1.17 builds for Qt 6 as it is). Keel's
`accounts/CMakeLists.txt` replaces upstream's qmake files with the same
defines.

## Sailfish.WebView.Popups, .Pickers and .Controls

sailfish-components-webview's dialogs, pickers and controls are Silica QML
plus three small C++ models; only their link to the engine is Gecko. They
are built here for Qt 6 from upstream (tag `1.8.0`), each file with its
upstream notice and an SPDX header added on top (`2026 Shipwright` added
where Keel changed it). Changes, each marked "Modified by Shipwright":

1. `popups/PopupOpener.qml`: wires a dialog's answer as soon as the page
   exists. Keel's PageStack creates pages synchronously, and the
   `pageCompleted` upstream waits for did not arrive for these pushes
   (follow-up in keel/silica).
2. `popups/LocationSettings.qml`: rewritten as a singleton with
   `locationEnabled: false`; upstream reads the system location setting
   through `com.jolla.settings.system`, which is Qt 5 only. The location
   dialog then also offers the settings link, as upstream does with location
   off.
3. `popups/UserPromptUi.qml`: `dialog: root.dialog` (in Qt 6 the plain name
   is DialogHeader's own property, a binding loop). `popups/PromptLabel.qml`:
   `onContentWidthChanged: function() { … }` (no injected parameter).
4. `pickers/SingleSelectPage.qml`, `MultiSelectDialog.qml`,
   `WebDatePickerDialog.qml`, `WebTimePickerDialog.qml`: Qt 5
   `Connections { onX: … }` written as `function onX() { … }`.
5. `controls/TextSelectionController.qml`: QOfono (the phone number "call"
   action) removed, `_canCall` is false. The controller is inert on Qt
   WebEngine, which draws its own selection handles and menu.
6. `controls/permissionmanager.cpp`, `permissionmodel.cpp`: reach
   Sailfish.WebEngine's `WebEngine` through the QML engine
   (`keelwebenginelink.h`, Keel's) instead of `SailfishOS::WebEngine`;
   PermissionModel connects to it in `classBegin()`, where its engine is
   known. The types are registered by Keel's `controlsforeign.h`
   (`QML_FOREIGN`, so the module has qmltypes) under upstream's names; the
   module imports Sailfish.WebEngine so that WebEngine is there.
7. `webengine/upstream/downloadhelper.*`: registered as Sailfish.WebEngine's
   `DownloadHelper` singleton with `QML_SINGLETON` (upstream registers it
   in its plugin).

Keel's own parts:

- The message bridge (`webview/qml/WebEngineBackend.qml`). Upstream's
  `PopupOpener` and `PickerOpener` listen for Gecko messages on the view
  (`addMessageListener`, `sendAsyncMessage`, `uniqueId`); the backend gives
  them that interface and turns Qt WebEngine's requests into those
  messages, and the answers back into the requests:

  | Qt WebEngine | Gecko message | Answer |
  | --- | --- | --- |
  | `JavaScriptDialogRequest` (alert, confirm, prompt; beforeunload as confirm) | `embed:alert`, `embed:confirm`, `embed:prompt` | `alertresponse`, `confirmresponse`, `promptresponse` |
  | `AuthenticationDialogRequest` (HTTP; proxy) | `embed:auth` | `authresponse` |
  | `featurePermissionRequested`: geolocation | `embed:permissions` | `embedui:permissions` |
  | `featurePermissionRequested`: camera, microphone | `embed:webrtcrequest` | `embedui:webrtcresponse` |
  | `ContextMenuRequest` on a link or image | `Content:ContextMenu` | (menu actions on the view) |
  | `FileDialogRequest` (open, open multiple) | `embed:filepicker` | `filepickerresponse` |
  | `ColorDialogRequest` | `embed:colorpicker` | `embedui:colorpickerresponse` |

  Other permission requests (notifications, screen capture, mouse lock)
  are refused, as Sailfish's WebView has no dialog for them; a page's
  "save file" and folder upload requests are refused. The context menu's
  "Save link" and "Save image" (with the view's `downloadsEnabled`) send
  `embedui:download`; the view starts the download with Qt WebEngine's
  link or image download action and saves it to the file the menu chose.
  A new window opens in the same view. An app's `popupProvider` replaces any
  dialog, as upstream.
- Remembered site permissions (`webengine/permissionstore.*`): Gecko's
  permission manager semantics (capability 1 allow, 2 deny; expiry never or
  session), kept in `keel-webview/permissions.json` in the app's data
  directory (`KEEL_WEBVIEW_PERMISSIONS` overrides it; session entries are
  not saved). "Don't ask again" in the dialogs writes it; the controls'
  `embedui:perms` requests (add, remove, get-all, get-all-for-uri) read and
  edit it and are answered with `embed:perms:all` and
  `embed:perms:all-for-uri`, as Gecko's (whether or not a PermissionManager
  observes them yet).
- Translations: Sailfish ships the compiled catalogues; Keel installs a
  fallback translator with the engineering English of every `qsTrId`
  (`webengine/webviewstrings.inc`, generated by `webview/strings.py` from
  the `//%` comments; MPL-2.0 like the strings it holds).
- `keel/silica/qml/private/Expander.qml`: the upstream context menu uses
  Silica's private `Expander`, which is not BSD in Silica 1.2.156; Keel's
  clean-room stand-in (keel/silica/PROVENANCE.md, "Keel stand-ins").

## org.nemomobile.mpris

qtmpris' MPRIS library, its qtdbusextended helper and its QML plugin,
compiled into one Qt 6 plugin (no C++ library is installed). An
`MprisPlayer` registers `org.mpris.MediaPlayer2.<serviceName>` on the
session bus, where Lipstick's media controls and any MPRIS client find it.
Upstream files keep their headers, with an SPDX header added on top.
Changes, each marked "Modified by Shipwright for Qt 6":

1. `qtdbusextended/dbusextendedabstractinterface.cpp`: `QVariant(type,
   ptr)`, `QDBusMetaType::typeToSignature(int)` and `demarshall(…, int, …)`
   take a `QMetaType` in Qt 6.
2. `src/mprismanager.cpp`: `QRegExp` wildcard matching replaced by
   `QRegularExpression::wildcardToRegularExpression()` (same match).
3. `src/mprisplayerinterface.cpp`: the `LoopStatus`/`PlaybackStatus`
   strings were initialised from enum values through an implicit `QChar`,
   ambiguous in Qt 6; they start as the MPRIS strings `"None"` and
   `"Stopped"`.
4. `src/mprisplayer_p.h`: no forward declaration of `QStringList`, an alias
   in Qt 6.
5. `declarative/plugins.qmltypes`: generated from Keel's Qt 6 build
   (qmlplugindump; revisions set to 256, Qt 6's encoding of 1.0), then
   brought to qmltyperegistrar's conventions, which qmllint 6 needs to
   resolve `on<Property>Changed` handlers: each property's
   `read`/`write`/`notify` from its `Q_PROPERTY`, a `Signal` entry for
   every notify signal, and `QString` for `string`.
   `declarative/qmldir` is Keel's.

## Amber.Web.Authorization

amber-web-authorization's OAuth library and its QML plugin, compiled into
one Qt 6 plugin (no C++ library is installed). The sign-in helpers open
the provider's page with `Qt.openUrlExternally` and read the reply from a
`RedirectListener` on a loopback port. Upstream files keep their contents,
with an SPDX header added on top (the files carry the Open Mobile Platform
LLC copyright; the LICENSE file names Jolla Ltd.). The library sources
build for Qt 6 unchanged. Changes, marked "Modified by Shipwright for Qt 6":

1. `import/plugin.cpp`: a gadget (value) type cannot have an upper-case QML
   name in Qt 6. `Error`'s enums are registered under `Error` with
   `qmlRegisterUncreatableMetaObject` (so `Error.NetworkError` and the
   other enum values still resolve), and the value type under `error`.
2. `import/OAuth2Ac.qml`, `OAuth2AcPkce.qml`, `OAuth2Implicit.qml`:
   `scopes` defaults to `[]`. Qt 6 refuses to pass an unset (undefined)
   `scopes` to `generateScope(QStringList, …)`, which Qt 5 took as an
   empty list.
3. `import/plugins.qmltypes`: generated from Keel's Qt 6 build
   (qmlplugindump; revisions set to 256, Qt 6's encoding of 1.0), then
   brought to qmltyperegistrar's conventions as for qtmpris above:
   `read`/`write`/`notify` from the `Q_PROPERTY` declarations, a `Signal`
   entry for every notify signal, and `QString` for `string`.

Keel's `amber-web-authorization/CMakeLists.txt` replaces upstream's qmake
files and builds `lib/` with `AMBER_WEB_AUTHORIZATION_LIBRARY_BUILD`, as
upstream's library build does.

## Amber.Mpris

amber-mpris' MPRIS library (namespace `Amber`), its qtdbusextended helper
(`Amber::Private`) and its QML plugin, compiled into one Qt 6 plugin (no C++
library or pkg-config file is installed). Upstream already builds for Qt 6
(its `rpm/amber-mpris-qt6.spec`, `QT_VERSION` checks in the sources); Chum
(chum:testing for 5.2, aarch64) ships that build as
`amber-qml-plugin-mpris-qt6` 1.2.9, at the same path, so Keel's
`-amber-mpris` subpackage conflicts with it and is not required by the
`shipwright-keel-platform` metapackage (either one serves Keel apps).

Licence: `COPYING` says LGPL version 2.1; the file headers say "version 2.1
of the License, or (at your option) any later version". Files with such a
header carry `LGPL-2.1-or-later`; the ones without (the forwarding headers
`src/Mpris`, `MprisClient`, `MprisController`, `MprisMetaData`,
`MprisPlayer`, `qtdbusextended/DBusExtended*`,
`src/mprismetadataproxy.*`, the D-Bus XML) carry `LGPL-2.1-only`, per
`COPYING`, with the year and author of their first commit. Upstream files
keep their contents, with an SPDX header added on top. Changes, marked
"Modified by Shipwright for Qt 6":

1. `declarative/mprisplugin.cpp`: `Mpris` is a `Q_GADGET`; Qt 6 takes a
   gadget for a value type and refuses its upper-case name, so
   `Mpris.Playing` and the other enum values were undefined. It is
   registered with `qmlRegisterUncreatableMetaObject` instead (as for
   amber-web-authorization's `Error` above).
2. `declarative/plugins.qmltypes`: generated from Keel's Qt 6 build
   (qmlplugindump; revisions set to 256), then brought to
   qmltyperegistrar's conventions as for qtmpris above.
   `declarative/qmldir` is Keel's (the same three lines as upstream's).

Keel's `amber-mpris/CMakeLists.txt` replaces upstream's qmake files:
qtdbusextended as a static library with `QT_DBUS_EXTENDED_LIBRARY`, the
library and plugin with `AMBER_MPRIS_LIBRARY` and `QT_NO_KEYWORDS`, as
upstream's `.pro` files. The QML `MprisPlayer` registers
`org.mpris.MediaPlayer2.<serviceName>.instance<pid>`, as upstream does.

## Nemo.Thumbnailer

nemo-qml-plugin-thumbnailer's cache library (`src/lib`) and QML plugin
(`src/plugin`), compiled into one Qt 6 plugin (no C++ library, headers or
pkg-config file are installed). The sources build for Qt 6 unchanged;
upstream files keep their contents, with an SPDX header added on top using
each file's copyright line (`nemothumbnailexports.h`, which has none: its
author and year from git, 2023 Jozef Mlich). Thumbnails go to the same cache
as the Qt 5 plugin (`~/.cache/org.nemomobile/thumbnails`, same keys and
JPEG files), so Qt 5 and Qt 6 apps share it. Images are read and scaled in
process (EXIF orientation applied); videos and PDFs run the system's
`/usr/bin/thumbnaild-video` and `thumbnaild-pdf` helpers (the open
github.com/sailfishos/thumbnaild, 0.1.2 in the 5.2 repository, BSD and
GPL-2.0-or-later; executables, so the Qt version does not matter), which the
`-thumbnailer` subpackage requires as the Qt 5 package does. Without them (the
host) a video thumbnail ends in `Thumbnail.Error`. The screen size used to
bound thumbnails comes from dconf through mlite (Chum's mlite-qt6) where it
is found, else upstream's 540x960 default (the host).

Keel's `thumbnailer/CMakeLists.txt` replaces upstream's qmake files
(`BUILD_NEMO_QML_PLUGIN_THUMBNAILER_LIB`, `HAS_MLITE5` with mlite6, Qt's
gui-private as `lib.pro`). Changes:

1. `plugin/plugins.qmltypes`: generated from Keel's Qt 6 build
   (qmlplugindump), keeping only the plugin's own types (`NemoThumbnailItem`,
   `NemoThumbnailLoader`, with the latter's `QThread` prototype given as
   `QObject`), then brought to qmltyperegistrar's conventions as for qtmpris
   above. `plugin/qmldir` is Keel's (upstream's three lines and
   `depends QtQuick`, which qmllint needs for `Item`'s members).

Not provided: the legacy `org.nemomobile.thumbnailer` import (the Qt 5
package's symlink) and the `libnemothumbnailer-qt6` C++ library.

## Nemo.Mce

libmce-qt's library and QML plugin, compiled into one Qt 6 plugin
(`Nemo/Mce/libqmcedeclarative.so`; no C++ library, headers or pkg-config
file are installed). The sources build for Qt 6 unchanged; upstream files
keep their contents, with an SPDX header added on top from each file's
copyright lines. libmce-qt has no licence file of its own (each file carries
the BSD-3-Clause text); `upstream-licenses/libmce-qt.LICENSE` is that text as
it stands in `lib/src/qmcedisplay.cpp`. The D-Bus proxies are generated from
upstream's `lib/dbus/*.xml` with the same `qdbusxml2cpp -N -c` class names
(`.license` sidecars give their year from git). The types follow MCE
(`com.nokia.mce`) on the system bus: the current state with its `get_*`
requests once MCE owns its name, then its `*_ind` signals; `valid` turns false
when MCE leaves the bus.

The MCE names come from mce-headers (`pkg-config mce`, the device's
`mce-headers` package, required with `KEEL_REQUIRE_MCE_HEADERS=ON` in the
spec). A host without them compiles against `mce/mce-dev/mce/`, a copy of
mce-dev's two headers (LGPL-2.1-only, unchanged apart from SPDX lines),
which the RPM does not install.

1. `plugin/plugins.qmltypes`: generated from Keel's Qt 6 build as for the
   modules above. `plugin/qmldir` is Keel's (upstream's three lines).

## Sailfish.Accounts

sailfish-components-accounts is open source (BSD-3-Clause, public at
github.com/sailfishos/sailfish-components-accounts, and the 5.2 package's
licence is BSD); earlier Keel notes called it proprietary, which was wrong. Its library (`src/lib`, the C++ API Account, AccountManager and
the rest) and QML plugin (`src/plugin`, including the Silica views) are
compiled into one Qt 6 plugin, `Sailfish/Accounts/libsailfishaccountsplugin.so`,
together with Qt 6 builds of the two libraries it links that have no Qt 6
package:

- libsignon-qt (`signon/`): the client of signond. Sailfish builds it with
  `CONFIG+=enable-p2p` and two patches (`0005-Guard-PendingCall-against-deletion-by-connected-slot`,
  `0006-Always-use-P2P-DBus-if-enabled`, applied), so it only talks to
  signond over its peer-to-peer socket. It builds for Qt 6 unchanged.
- libbuteosyncfw's profile and client parts (`buteosyncfw/`): the sync
  profiles AccountSyncManager creates and edits for msyncd, and the msyncd
  D-Bus client. msyncd itself stays the system's Qt 5 daemon.

libaccounts-qt is Keel's accounts-qt6 (above). libsailfishkeyprovider and
sailfish-access-control (open C libraries, LGPL) are linked from the system
on the device (`KEEL_REQUIRE_SAILFISH_ACCOUNTS_DEPS=ON` in the spec); a host
without them builds without the key provider (upstream's own
`USE_SAILFISHKEYPROVIDER` switch) and with Keel's `sailfish-accounts/compat/`
`sailfish_access_control_hasgroup()` (the user's groups from the system
databases). The plugin loads Sailfish's existing Qt 5 translation files.

Upstream files keep their contents (sailfish-components-accounts already has
SPDX headers; the others get one on top from their copyright lines, and the
forwarding headers without one the year and author of their first commit).
Changes, each marked "Modified by Shipwright for Qt 6":

1. `sailfish-accounts/plugin/plugin.cpp`: the gadget
   `AccountAuthenticatorCredentials` is registered under a lower-case QML
   name, which Qt 6 requires of value types (QML only meets it as a value).
2. `sailfish-accounts/lib/accountmanager.cpp`, `service.cpp`,
   `servicetype.cpp`, `servicemodel.cpp`: `QSet::fromList()` and
   `QSet::toList()` replaced.
3. `sailfish-accounts/lib/accountsyncmanager.cpp`: `Profile::allKeys()` is a
   `QMultiMap` (change 5).
4. `buteosyncfw/common/SyncCommonDefs.h`: Qt 6 has no
   `QNetworkConfiguration`; the connection types keep Qt 5's
   `BearerType` numbers, which profiles written by msyncd hold.
5. `buteosyncfw/profile/Profile*`: the key maps are `QMultiMap`s (Qt 5's
   `QMap` held several values per key): `insertMulti()` becomes `insert()`,
   a plain `insert()` (which replaced) becomes `replace()`, `operator[]`
   becomes `value()`.
6. `buteosyncfw/profile/SyncProfile.cpp`, `SyncSchedule.cpp`:
   `QSet::toList()`, `QString::SkipEmptyParts`, a `QFlags` from `0`.
7. `buteosyncfw/clientfw/SyncDaemonProxy.h`: `qVariantFromValue()`.
8. `sailfish-accounts/plugin/plugins.qmltypes`: generated from Keel's Qt 6
   build as for the modules above.

Keel's `sailfish-accounts/CMakeLists.txt` replaces upstream's qmake files
(libsignon-qt with `ENABLE_P2P` and its `QT_NO_CAST_*` defines; the
`<buteosyncfw5/SyncClientInterface.h>` include path is generated).

## Sailfish.Policy

Sailfish's `sailfish-policy` 0.4.26 is proprietary (package licence
"Proprietary", source on Jolla's private bitbucket); Keel's library and
plugin are clean-room. Sources, all from the 5.2.0.15 aarch64 packages
`sailfish-policy`, `-devel`, `-doc` and `-examples` and from public usage:

- the public headers (`accesspolicy.h`, `accesspolicyplugin.h`,
  `policytypes.h`, `policyvalue.h`): class, property, method and signal
  names, the policy types and their values. Keel's headers declare the same
  API in its own words;
- the documentation (`/usr/share/doc/sailfish-policy`): what each type and
  property means, PolicyValue's one-to-one type/key mapping;
- the QML module's `qmldir` and `plugins.qmltypes`: `AccessPolicy` is a
  singleton, `PolicyValue` creatable;
- file names and strings visible in the shipped files (no code read or
  decompiled): the library opens `/var/lib/policy/policy.conf` with GLib's
  key file API (`g_key_file_get_boolean`), group `policy`; the example
  plugin's strings show the keys are the policy type names
  (`CameraEnabled`, ...); `/var/lib/policy` is the package's directory
  (`root:sailfish-mdm`, mode 775); the library loads
  `%{_libdir}/libsailfishpolicy/plugin/libsailfishpolicyplugin.so` when
  present; privacy mode comes from `org.sailfishos.privacyswitch` at
  `/privacyswitch` (strings of the library and of `sailfish-privacyswitch`'s
  `privacyswitchd`, a session daemon whose adaptor names its interface
  `org.sailfishos.privacyswitch`, the method `privacyModeActive` and the
  signal `privacyModeActiveChanged(active)`);
- jolla-camera (github.com/sailfishos/jolla-camera, BSD-3-Clause, commit
  `f8777bafeb92c301ff2b98e929e8dfa342bb342e`): `AccessPolicy.cameraEnabled`
  and `AccessPolicy.microphoneEnabled` read from QML.

Keel's decisions, where the shipped files say nothing: the store is read
only (the MDM setters return false); a policy policy.conf does not
mention is enabled (no MDM restriction); anything Keel cannot read (no
directory, an unreadable or malformed file, a non-boolean value, or the Qt
5 plugin installed, which Qt 6 cannot load) reads as disabled, and
`PolicyValue.value` as undefined, never as enabled. The
`enable_flight_mode_policy` marker in `/var/lib/policy` only gates writing
in Sailfish's library and is not read. `plugin/plugins.qmltypes` was
generated from Keel's plugin.

## Keel's own files

Everything under `media/`, `pickers/`, `gallery/`, `webview/`, `webengine/`,
`webengine-policy/`, `common/`
and `tests/`, the CMake files, `amber-mpris/declarative/qmldir`,
`thumbnailer/plugin/qmldir`, `mce/plugin/qmldir`,
`sailfish-accounts/compat/`, `policy/`,
`secrets/qml/Sailfish/*.qmldir`, `secrets/sailfish-qt6.pc.in`,
`accounts/*.qmldir`, `accounts/accounts-qt6.pc.in`, this file and README.md
are Shipwright-licensed, except sailfish-components-webview's MPL-2.0 files
(`webview/popups/`, `webview/pickers/`, `webview/controls/` but
`controlsforeign.h` and `keelwebenginelink.h`, `webengine/upstream/`,
`webengine/webviewstrings.inc`). The accounts test data (`tests/accounts/data/`) is
nemo-qml-plugin-accounts' BSD test data.
