<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# Keel platform modules

Qt 6 versions of the Sailfish platform QML modules that native Sailfish apps
import besides Silica and the Nemo plugins. Origins: [PROVENANCE.md](PROVENANCE.md).
Package: `keel/rpm/shipwright-keel-platform.spec` (one subpackage per module).

| Module | What works | Partial or missing |
| --- | --- | --- |
| `Sailfish.Media 1.0` | `MediaKey` (keys grabbed through Lipstick's `GRABBED_KEYS` window property, taken before the focused item, `pressed`/`released`/`repeat`), `MediaPlayerControls` enums, `MetadataReader.getTitle()` (ID3, Vorbis comment, FLAC tags), `MediaListItem`, `MediaPlayerControlsPanel`, `MediaPlayerPanelBackground`, `MprisPlayerControls` (the lock screen's media controls: a Loader whose item shows and controls the current MPRIS player through Amber.Mpris) | the panel, list item and MPRIS controls have Keel's own look; `MprisPlayerControls`' item is null without Amber.Mpris |
| `Sailfish.Pickers 1.0` | all 16 documented pages and dialogs; images, videos, music and documents from Tracker 3 (falls back to a scan of home and memory cards); downloads, files and folders from the file system | thumbnails by Qt image scaling (no video frames); Keel's own layout |
| `Sailfish.Gallery 1.0` | `ThumbnailImage` (a pressable square thumbnail of a photo, cropped to fill; `source`, `size`, `mimeType`, `duration`, `selected`, `status`, `clicked`/`pressAndHold`), `ImageViewer` (a photo fitted to the view, pinch or double-tap to zoom, pan while zoomed; `source`, `active`, `viewMoving`, `zoomed`, `error`, `clicked`, `zoomOut()`); clean-room from the types' use in apps | videos show the theme's video icon (no frame extraction); no `VideoPoster`, `GalleryItem` or the Gallery app's own pages |
| `Sailfish.WebView 1.0`, `Sailfish.WebEngine 1.0` | every member of the WebView documentation (stable, additional and experimental attributes) and of WebEngine's, on Qt WebEngine (Chromium, Chum's `qt6-qtwebengine`), in process: private mode, user agent and `desktopMode`, JavaScript, images, popups, CORS preferences, link and redirect signals, `runJavaScript` with Sailfish's contract, `pixelRatio` (Sailfish's default, as the page zoom), `crashed`, `security` (Keel's own TLS check of the page's server), frame scripts and the message manager, selection, input focus, scroll geometry and the chrome gesture, downloads, user style sheets, Gecko's clipboard, download and site permission topics; with Keel.WebEngine (`-webview-qtwebengine`) also `cookieBehavior`, `doNotTrack` and `colorScheme`; without Qt WebEngine a placeholder that opens the page in the browser | not Gecko: frame scripts have Gecko's message-manager globals but no XPCOM; `colorScheme` and `setIsAccelerated` are read once, when the app's first WebView starts Qt WebEngine; `security` reports no mixed content (Qt WebEngine does not tell); `pinching` is always false |
| `Sailfish.WebView.Popups 1.0`, `Sailfish.WebView.Pickers 1.0`, `Sailfish.WebView.Controls 1.0` | sailfish-components-webview's own (MPL-2.0) dialogs and pickers for the page's requests on Qt WebEngine: alert, confirm, prompt, sign-in, location and camera/microphone permission (remembered with "don't ask again"), link and image context menu with "Save link" and "Save image", file upload, colour; an app's `popupProvider`; `PermissionModel` and `PermissionManager` over the remembered permissions | date/time and `<select>` pickers and password manager prompts are not raised (Chromium draws its own); `TextSelectionController` is inert (Chromium's own selection) |
| `Sailfish.Secrets 1.0`, `Sailfish.Crypto 1.0` | upstream sailfish-secrets client libraries and QML plugins built for Qt 6 (`libsailfishsecrets-qt6`, `libsailfishcrypto-qt6`, headers under `include/sailfish-qt6`, pkg-config `sailfishsecrets-qt6`, `sailfishcrypto-qt6`), talking to the system's `sailfishsecretsd` | the in-app authentication view (`ApplicationInteractionView`) is untested |
| `org.nemomobile.accounts 1.0`, `libaccounts-qt6` | upstream nemo-qml-plugin-accounts (Qt 6 port) and libaccounts-qt 1.17 over the system accounts database (libaccounts-glib) | sign-in is Sailfish.Accounts' (below) |
| `Sailfish.Accounts 1.0` | upstream sailfish-components-accounts (BSD) for Qt 6 on libaccounts-qt6: `Account` (configuration, services, `createSignInCredentials()`, `signIn()` through signond), `AccountManager`, `AccountModel`, `Provider`/`Service`/`ServiceType` and their models, `SignInParameters`, `AccountAuthenticator`, `AccountValue`, `AccountSyncManager`/`AccountSyncOptions`/`AccountSyncSchedule` (msyncd's sync profiles), and the Silica views (`AccountsListView`, `AccountsFlowView`, `AccountProviderPicker`, `AccountIcon`); libsignon-qt and libbuteosyncfw built for Qt 6 inside the plugin | sign-in and sync not run on a device; no C++ library |
| `org.nemomobile.mpris 1.0` | upstream qtmpris for Qt 6: `MprisPlayer` publishes the app as an MPRIS player on the session bus (status, metadata, capabilities; Play, Pause, PlayPause, Next, Previous, Seek, ... reach the QML handlers), `MprisManager`, `Mpris` | none known |
| `Amber.Web.Authorization 1.0` | upstream amber-web-authorization for Qt 6: `OAuth1`, `OAuth2Ac`, `OAuth2AcPkce`, `OAuth2Implicit`, `RedirectListener`, the `OAuth10a`/`OAuth2Ac`/`OAuth2AcPkce`/`OAuth2Implicit` QML helpers and the `Error` enums | the error value type is named `error` in QML (Qt 6 does not allow upper-case value type names); no C++ library or pkg-config file |
| `Amber.Mpris 1.0` | upstream amber-mpris for Qt 6: `MprisPlayer` publishes the app as an MPRIS player on the session bus (as `org.mpris.MediaPlayer2.<serviceName>.instance<pid>`; status, `metaData`, capabilities; Play, Pause, PlayPause, Next, Previous, Seek, ... reach the QML handlers), `MprisController` follows and controls the other players, `Mpris` enums, `MprisMetaData`. Package `-amber-mpris`, or Chum's `amber-qml-plugin-mpris-qt6` (the same upstream; they conflict) | no C++ library or pkg-config file |
| `Nemo.Thumbnailer 1.0` | upstream nemo-qml-plugin-thumbnailer for Qt 6: `Thumbnail` (source, sourceSize, fillMode, priority, mimeType, status) and `image://nemoThumbnail/<path>`, in the cache Qt 5 apps use; images in process (EXIF orientation applied), videos and PDFs through the system's thumbnaild helpers | no `org.nemomobile.thumbnailer` legacy import; no C++ library |
| `Sailfish.Policy 1.0`, `libsailfishpolicy-qt6` | `PolicyValue` (`policyType`, `key`, `value`, the static `keyValue()`) and the `AccessPolicy` singleton (every policy as a bool, `privacyModeActive`), with Sailfish's C++ API (`include/sailfishpolicy-qt6`, pkg-config `sailfishpolicy-qt6`), reading the policies MDM applications set in `/var/lib/policy/policy.conf`, followed for changes, and the privacy switch daemon. Fail-closed: a policy is true only when the store was read and no MDM disabled it | read only: the MDM setters return false; Sailfish's Qt 5 access policy plugin cannot be loaded, so while one is installed every policy reads as unknown (false) |
| `Nemo.Mce 1.0` | upstream libmce-qt for Qt 6: `MceDisplay`, `MceTkLock`, `MceBatteryLevel`, `MceBatteryState`, `MceBatteryStatus`, `MceCableState`, `MceChargerState`, `MceChargerType`, `MceChargingState`, `McePowerSaveMode`, `MceCallState`, `MceNameOwner`, following MCE on the system bus | no C++ library |

## Build and test

Part of the Keel CMake project (`KEEL_BUILD_PLATFORM`, on by default):

```
cmake -S keel -B <build> -G Ninja && cmake --build <build>
ctest --test-dir <build> -R keel_platform
```

`keel_platform_media` (offscreen): MediaKey takes its key before the
focused item; press, auto-repeat and release; disabled keys pass through;
`GRABBED_KEYS` on existing windows and on windows created later, cleared
when the MediaKeys go; title tags of ID3v2.3/2.4, ID3v1, FLAC, Ogg Vorbis
and Opus files; the QML types load on Keel's Silica.

`keel_platform_mpris_player_controls` (private D-Bus): `MprisPlayerControls`
set up as Jolla's lock screen does (LockItem.qml) follows a fake MPRIS
player another connection publishes: not enabled before the player
appears, then enabled with its title and artists and `isPlaying`; tapping
play-pause, next and previous emits the `*Requested` signals and reaches the
player, whose status and track changes come back; the lock screen can turn
it off (`enabled = false`).

`keel_platform_pickers`: content models on a fake home (categories, newest
first, hidden files and music cover art left out, name filters, search,
selection), the folder model, Tracker's cursor format, and the Tracker
source against a fake Tracker endpoint (600 rows, more than a pipe buffer).
`keel_platform_pickers_qml`: every picker page and dialog driven as apps use
them (tap, selection, return to the app page, folder navigation).

`keel_platform_accounts` (private D-Bus and accounts database; registered
only where libaccounts-glib is found, on Ubuntu `libaccounts-glib-dev`): an
account created from QML is in the database for the C++ API, an account
another client adds appears in the QML model (libaccounts-glib's D-Bus
change notification), providers and services are listed.

`keel_platform_webview_engine`: the WebView API over a test double of Qt
WebEngine's QML module (navigation, history, `runJavaScript` contract,
link and redirect signals, profiles, settings and preferences, observers).
`keel_platform_webview_api`: the rest of the WebView API over the test
double (crashed, javascriptEnabled, security, scroll geometry and chrome,
desktopMode, frame scripts and messages through the bridge, selection,
copying and input focus, downloads, user style sheets, WebEngine's
lifecycle, WebViewFlickable's header, Silica's SilicaWebView). The
WebView tests keep remembered site permissions in the build tree
(`KEEL_WEBVIEW_PERMISSIONS`) and make no TLS connections of their own to
the test URLs' hosts (`KEEL_WEBVIEW_CERTIFICATES=0`; the `security`
object then has its state without certificate details).
`keel_platform_webview_popups`: the popups, pickers and controls over the
same test double (alert, confirm and prompt answers reach the request,
sign-in, a remembered geolocation permission, a link's context menu, a
file upload opens the content picker, an app's popupProvider,
PermissionModel on the remembered permissions).
`keel_platform_webview_external`: the fallback where Qt WebEngine is
missing.
`keel_platform_webview_qtwebengine` (registered only where Qt WebEngine's
C++ API is found, on Ubuntu `qt6-webengine-dev` and
`qml6-module-qtwebengine`): a WebView on the real Qt WebEngine (offscreen,
Chromium's sandbox off) against a local HTTP server. `BlockThirdParty`
keeps 127.0.0.1's cookie and drops the one a localhost image sets,
`AcceptAll` keeps both, `BlockAll` neither; requests carry `DNT: 1` while
`doNotTrack` is set; `FollowsAmbience` under the default LightOnDark
ambience gives the page a dark `prefers-color-scheme`; the page is 320 /
`pixelRatio` CSS pixels wide; a page's `confirm()` and `prompt()` are
answered through Sailfish.WebView.Popups' dialogs; a frame script answers
the app's message with the page's title and the colour WebEngine's user
style sheet gave it, and a selection made by the page is reported; a
self-signed local TLS server makes `security` broken and untrusted with
its certificate's names and the session's protocol and cipher (the
certificate is made with openssl at run time; skipped without it); Silica's
SilicaWebView exchanges `navigator.qt` messages with the page.

`keel_platform_sailfish_policy` (private D-Bus): against a temporary policy
directory and a fake privacy switch daemon. No directory: every policy
unknown; an empty one: all enabled; policies an MDM writes (GLib's
write-and-rename) are followed with change signals per property; a
non-boolean value is false; a file that is not a key file, a directory in
its place or an installed Qt 5 access policy plugin make every policy
unknown; the setters return false and write nothing; `privacyModeActive`
is read from the daemon and follows its signal; jolla-camera's QML use
(`AccessPolicy.cameraEnabled`, `.microphoneEnabled`) and `PolicyValue` by
type and by key.

`keel_platform_mpris` (private D-Bus): hutspot's `MprisPlayer` use; a plain
D-Bus MPRIS client reads Identity, PlaybackStatus, CanGoNext and the
metadata, and its Next and PlayPause calls reach the QML handlers.

`keel_platform_amber_mpris` (private D-Bus): a QML `MprisPlayer` is read
by a plain D-Bus MPRIS client (Identity, DesktopEntry, PlaybackStatus,
capabilities, Metadata with microsecond `mpris:length`, GetAll); the
client's Next, PlayPause and Seek reach the QML handlers and a disallowed
Previous is an error; an `MprisController` finds a player another
connection publishes (a plain D-Bus adaptor), reads its identity, title,
capabilities and status, and its `next()` reaches that player.

`keel_platform_thumbnailer` (offscreen, private `XDG_CACHE_HOME`): three
`Thumbnail` items render a 400x200 picture fitted, cropped, and from a JPEG
whose EXIF orientation turns it upright (pixels checked in a window grab);
the thumbnails land in the cache; `image://nemoThumbnail` answers with a
cropped square and serves a cached thumbnail after the original is gone; a
video with no `thumbnaild-video` (the host) ends in `Thumbnail.Error`.

`keel_platform_mce` (private bus as the system bus, fake MCE): every type
is invalid before MCE is on the bus, reads MCE's state with its `get_*`
requests once it appears (display, tklock, battery level, cable, power save,
call state, name owner), follows the display, tklock, battery level and
state, cable, charger state and type, power save and call state signals,
and turns invalid when MCE leaves the bus.

`keel_platform_sailfish_accounts` (private bus and accounts database, a
fake signond on its peer-to-peer socket `$XDG_RUNTIME_DIR/signond/socket`):
`AccountManager` lists the test provider, service and service type and
creates an account that the C++ API then finds; an `Account` writes its
display name, a global and a per-service configuration value and the service
state, which the C++ API and a fresh `Account` read back;
`createSignInCredentials()` stores the identity in signond (`store`, with the
user name), runs its session (`process`) and records the credentials, and
`signIn()` runs the session again, both returning signond's reply;
`AccountModel` lists the account; `AccountSyncManager` loads with no
profiles; `AccountsListView` and `AccountProviderPicker` load on Keel's Silica
and list the account.

`keel_platform_amber`: sfos-forum-viewer's login use; the module loads,
`OAuth1.parseRedirectUri()` reads the redirect's parameters, a
`RedirectListener` listens on a loopback `http://` URI, and an HTTP request
to it reaches `onReceivedRedirect`.

`keel_platform_secrets` (private D-Bus): sfos-forum-viewer's
`GenerateKeyRequest` and `DecryptRequest` QML, and a
`CollectionNamesRequest`, against a fake `sailfishsecretsd` (discovery on the
session bus, peer-to-peer `QDBusServer`, each call's signature checked
against the daemon's introspection data, replies built without the
library's marshalling); a key serialised by upstream's Qt 5 build reads back
identically, and the Qt 6 bytes are the ones Qt 5 was checked to read.

## Needs device verification

Not run on a device. On Sailfish OS 5.2 with Chum's Qt 6 and Keel.

Sailfish.Media:

1. Start foilauth or yubikey through Keel's direct mode (Lipstick as the
   compositor), open the scan page and press volume up/down: the zoom
   changes, the system volume does not. hutspot: headset play/pause and
   next/previous reach the app while another app is in front.
2. Check (Lipstick debug output) that the window's `GRABBED_KEYS` arrives.
   This needs Keel's direct mode, where the app's own window is Lipstick's
   surface; when the app is nested in keel-shell, keel-shell's window would
   have to carry the property instead (not done).
3. Whether Lipstick also wants the app to hold the HeadsetButtons /
   ScaleButton resource (Keel's Nemo.Policy asks the resource policy
   manager for it, as Qt 5 apps do).
4. Whether key repeat arrives: Lipstick forwards no auto-repeats; the Qt
   Wayland client's own key repeat should produce `repeat()`.

Sailfish.Secrets / Sailfish.Crypto:

1. sfos-forum-viewer's login (key generation, then decryption of the
   forum's reply) against the real `sailfishsecretsd`; the app needs the
   Sailjail `Secrets` permission (it whitelists
   `$XDG_RUNTIME_DIR/sailfishsecretsd` and the discovery call). The Crypto
   discovery service is not in that permission, so the library connects
   through the socket fallback, as Qt 5 apps do.
2. A daemon-side prompt (device lock) shows when an app asks for it.

Sailfish.Pickers:

1. bitsailor's "Choose file" and sfos-forum-viewer's image upload: the
   picker lists files from Tracker (the model's `source` is "tracker"). The
   app needs the Sailjail `MediaIndexing` permission for Tracker (it allows
   `org.freedesktop.Tracker3.Miner.Files`), and files outside its other
   permissions (Pictures, Documents, ...) are not readable.
2. Sailfish 5.2's Tracker 3 writes the cursor format checked here (that of
   Tracker 3.1 to 3.7).

Accounts:

1. `org.nemomobile.accounts` lists the accounts made in Settings. The app
   needs the Sailjail `Accounts` permission, which maps the privileged
   `Accounts` data directory where Sailfish keeps the accounts database
   (sailjail-permissions, `Accounts.permission`) and lets the app own
   `com.google.code.AccountsSSO.Accounts.*` for the change notifications.
   Check that libaccounts-glib finds the database there for a Qt 6 process
   as it does for Qt 5 apps.


WebView:

1. Install `qt6-qtwebengine` from chum:testing; open sailhn's or dee's
   article view and sfos-forum-viewer's login. Qt WebEngine wants
   `QtWebEngineQuick::initialize()` (or `Qt::AA_ShareOpenGLContexts`)
   before the QGuiApplication exists; Keel's SailfishApp does not do that
   yet (follow-up below). Chromium's sandbox inside Sailjail may need
   `QTWEBENGINE_DISABLE_SANDBOX=1`. Rendering through Lipstick (OpenGL ES),
   touch input and the Sailjail `WebView`/`Internet` permissions are
   unverified.
2. Without `qt6-qtwebengine`, the WebView shows the address and opens it in
   the browser.
3. Page scale: a page's text is as large as in the Sailfish Browser (both
   use 1.5 times `Theme.pixelRatio`, rounded).
4. `security`: Keel's own TLS connection to the page's server must be
   allowed by Sailjail as the page's is (`Internet`), and must see the
   system's CA certificates (`/etc/pki`): a known https site gives
   `allGood`.
5. Frame scripts: an app's frame script (for example a page scraper)
   reaches the app through the console bridge on the device's Qt
   WebEngine 6.8 as on the host's 6.4.
6. Dialogs: a site asking for the location shows Sailfish's location dialog
   (Sailjail `Location` permission for the app); "don't ask again" survives
   an app restart; a long press on a link opens the context menu, and a file
   upload opens the content picker.

Policy:

1. On a device without MDM, `/var/lib/policy` exists (sailfish-policy)
   and jolla-camera built for Keel shows the viewfinder, not "disabled by
   MDM". Check that a Sailjailed app can read `/var/lib/policy` (if not,
   every policy reads as disabled).
2. With a policy set by an MDM (or `/usr/libexec/policy-updater` and a
   `CameraEnabled=false` line written as root), the app follows it, and
   the privacy switch on devices that have one sets `privacyModeActive`.

MPRIS:

1. hutspot playing: the lock screen's media controls show the track and
   its buttons control the app. The app needs the Sailjail permission that
   lets it own `org.mpris.MediaPlayer2.*` (`Audio` in sailjail-permissions).

Amber.Mpris:

1. A player built on Amber.Mpris shows in the lock screen's media controls
   (Lipstick follows `org.mpris.MediaPlayer2.*`, including the
   `.instance<pid>` names), and the buttons reach its handlers. Same Sailjail
   permission as above.
2. Installing `-amber-mpris` where Chum's `amber-qml-plugin-mpris-qt6` is
   installed is refused by the declared conflict (and the other way round).

Nemo.Thumbnailer:

1. A video and a PDF get thumbnails through thumbnaild's helpers (Sailjail:
   the app may need to run them; check that `thumbnaild-video` starts from a
   sandboxed Keel app).
2. A thumbnail made by a Qt 5 app (Gallery) is served to a Keel app from the
   shared cache, and the other way round.

Nemo.Mce:

1. On the device the values match `mcetool` (display, lock, battery), and
   Sailjail lets a Keel app read MCE (as it does for Qt 5 apps).

Sailfish.Accounts:

1. A Keel app lists the accounts made in Settings with `AccountsListView`,
   and `createSignInCredentials()` / `signIn()` against signond work for a
   sandboxed Keel app (signond's access control decides by the calling
   process; check that a Qt 6 client is let in as Qt 5 apps are).
2. `AccountSyncManager` creates and edits sync profiles msyncd then runs
   (profiles written by the Qt 6 build must read the same in Qt 5 msyncd).

Amber.Web.Authorization:

1. sfos-forum-viewer's login: its WebView shows the forum's key page, and
   the redirect to the loopback `RedirectListener` comes back to the app
   (Sailjail `Internet` permission). Apps using the `OAuth2Ac`-style helpers
   open the sign-in page in the system browser instead, which must reach
   `127.0.0.1` for the redirect.

## WebView: options considered

| Option | Verdict |
| --- | --- |
| Port qtmozembed (EmbedLite Gecko) and sailfish-components-webview to Qt 6 | The faithful route (same engine as the browser) but large: qtmozembed renders through Qt 5's scene graph and GL context sharing, the components are Qt 5 Silica QML, and every Gecko update would need the port maintained. Not started. |
| Out-of-process Qt 5 WebView embedded as a Wayland subsurface | Not possible: a subsurface must belong to the same Wayland client, and Lipstick offers no cross-client embedding protocol. |
| Hand pages to sailfish-browser (`org.sailfishos.browser`) | Works for "open this page", but the app loses the page: no URL changes (OAuth redirects), no `runJavaScript`, no `loaded`. Kept as the fallback when no engine is installed (Qt.openUrlExternally). |
| QtWebView module | Its Qt 6 backends are Qt WebEngine or platform engines that Sailfish lacks; no gain over Qt WebEngine directly. |
| **Qt WebEngine in process** | Chum's chum:testing has `qt6-qtwebengine` 6.8.4 for aarch64 (77 MB, with `QtWebEngine` QML, `libQt6WebEngineQuick`). Chosen: the Sailfish API maps onto it (table in PROVENANCE.md), apps keep their own control of the page. |


## Follow-ups outside keel/platform

- keel/sailfishapp: call `QtWebEngineQuick::initialize()` when the app links
  Qt WebEngine, or set `Qt::AA_ShareOpenGLContexts` before creating the
  QGuiApplication (cheap and harmless), so Qt WebEngine works when it is
  loaded from Sailfish.WebView.
- keel/silica: a dialog pushed by sailfish-components-webview's
  `PopupOpener` (`pageStack.animatorPush`) never emitted the
  `pageCompleted` upstream waits for, although a plain Silica test of
  `animatorPush` sees it; PopupOpener is patched to wire the dialog at once
  (PROVENANCE.md). Find out why and drop the patch.
