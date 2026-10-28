<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: Apache-2.0
-->

# Reef client UI

The Reef store client's QML, written against Keel (`import Sailfish.Silica 1.0` under Qt6, versionless `import QtQuick`). It uses Keel's Silica components: ApplicationWindow, Page, PageStack, Dialog, DialogHeader, PageHeader, PullDownMenu, MenuItem, ContextMenu, SilicaFlickable, SilicaListView, VerticalScrollDecorator, ListItem, Label, Theme, CoverBackground, CoverActionList, CoverAction, TextField (with `EnterKey`), TextSwitch, ComboBox, Button, SectionHeader, DetailItem, RemorsePopup, BusyIndicator, ProgressBar, ProgressCircle, Icon and ViewPlaceholder. The pages follow the Sailfish UI rules (`tools/lint/lint.sh style`). Everything else is plain QtQuick (`Column`, `Row`, `Repeater`, `Item`).

**Developer text is plain text.** Titles, summaries, descriptions, categories, publishers and permission names come from developers through the unsigned catalogue. The window sets `_defaultLabelFormat: Text.PlainText`, so every Silica label (PageHeader, SectionHeader, ViewPlaceholder, ListItem rows) shows markup as text; the delegates and the description also set `textFormat: Text.PlainText` explicitly. A catalogue cannot make the store load remote images or show links.

**Assets.** Icons and screenshots are the only images, and they come from the store directory alone: the catalogue names them by a path relative to its own directory (`assets/...`, checked by `catalogue::is_asset_path`, never a URL), the Rust side downloads them during a refresh from that directory (`jobs::fetch_assets`: PNG or JPEG by magic number, 2 MB at most, cached under `$XDG_CACHE_HOME/shipwright-reef/assets/`), and the UI shows the cached local files (`iconPath`, `screenshotPaths`). A path not cached yet is empty, and `AppIcon` shows the app's initial instead.

**Links.** Only `https://` URLs are opened (`components/Texts.js`, `isHttps` and `openHttps`); the Homepage, Source and Buy actions are hidden for anything else. reef-backend drops non-https homepage and source links and refuses a non-https purchase URL when it parses the catalogue.

**Translation.** The Rust side sends keys, not English, for what it says itself (`busyText`, and the fixed messages in `lastError`), and `components/Texts.js` maps them to `qsTr` strings. Errors that come from the network or reef-licence are shown as they are.

**Errors.** A failed refresh is in `lastError`, shown on the catalogue, installed and licences pages. A licence that verifies but cannot be stored is reported on the licences page.

**Installs.** Installing, updating and removing are not available on Marathon yet: the package page's Install button is disabled with a note saying so.

The delegates take their roles as `required property` declarations. `pragma ComponentBehavior: Bound` is not used: it needs Qt 6.5, and the host's Qt is 6.4 (the device has 6.8).

```
ui/
  shipwright-reef.qml          ApplicationWindow; refreshes on start if enabled; on becoming
                               active, fetches the licence of a pending web purchase
  pages/CataloguePage.qml      the store's home: the Featured banners, the collections as
                               rows, the categories, All apps
  pages/BrowsePage.qml         one category's, one collection's or every app, a list
                               built as it scrolls (browseModel)
  pages/SearchPage.qml         the search field and ranked results
  pages/PackagePage.qml        icon and publisher, screenshots, details, permissions and
                               sandboxing, buy (with a hint until the licence arrives);
                               Install disabled, with a note; links in the pull-down menu
  pages/InstalledPage.qml      installed Reef packages (none until installs come)
  pages/LicencesPage.qml       stored licences and their status; add, refresh, forget
                               (context menu with remorse)
  pages/AddLicenceDialog.qml   paste a token; accepted only once it verifies
  pages/SettingsPage.qml       arch and the store's address, refresh on open, licence
                               service URL (https only, saved on Enter or leaving)
  cover/CoverPage.qml          what Reef is doing; refresh action
  components/PackageDelegate   a package row (ListItem, required properties): icon, title,
                               "New", publisher, summary, state
  components/FeaturedDelegate  a Featured tile: icon with the title under it
  components/CollectionRow     a collection: a section header and a row of tiles from
                               Reef.appRow, ending in SeeAllTile
  components/SeeAllTile        a row's last tile: opens the whole collection
  components/CategoryTile      a category: theme icon and name, one line
  components/AppIcon           a cached launcher icon, or the app's initial until it is
  components/Texts.js          translations of the Rust side's keys; https link rule
```

## Backend object API

The UI imports `Shipwright.Reef 1.0` and uses a singleton named `Reef`. The CXX-Qt bridge (`src/bridge.rs`) implements it over `reef-backend`, and the bridge also does the network fetches, since the backend crate has no HTTP stack. This is the contract between the two sides.

### Properties

| Property | Type | Meaning / backend source |
| --- | --- | --- |
| `arch` | string | the phone's architecture (`std::env::consts::ARCH`) |
| `storeUrl` | string | the store directory the catalogue comes from (`jobs::store_url`) |
| `busy` | bool | a refresh is running |
| `busyText` | string | a key for the running job (`refreshing`, `refreshing_licences`); `Texts.busyText()` translates it |
| `lastError` | string | last refresh error, or empty; lines starting with U+001E are keyed messages for `Texts.message()` |
| `revision` | int | changes on every model rebuild; bind `pkg: Reef.revision, Reef.packageDetails(name)` so details follow refreshes and licence changes |
| `catalogueModel` | model | packages this phone's processor runs (`catalogue.visible` joined by `store::entries`) that match `searchText` |
| `installedModel` | model | same roles, only rows whose `installState` is not `not_installed` |
| `featuredModel` | model | same roles, the catalogue's `featured` names that are visible, in its order |
| `licenceModel` | model | stored licences (`LicenceStore::list`) |
| `categoriesModel` | model | `categoryId`, `label`, `icon` (a Silica theme icon name, or empty), `count`: the store index's categories that have apps shown on this phone, in its order; from a `catalogue.json`, one per category its apps name (`rows::category_rows`) |
| `collectionsModel` | model | `collectionId`, `title`, `subtitle`, `generated`, `apps` (RPM names shown here, in order): the store index's collections with at least three apps shown here (`rows::collection_rows`, `MIN_COLLECTION_APPS`) |
| `browseModel` | model | package roles: one category's, one collection's or every app, as `browse()` last set it |
| `detailsLoading` | string | the app whose details `loadDetails()` is fetching, or empty |
| `searchText` | string, rw | the search page's field; `catalogueModel` keeps the rows where every whitespace-separated word matches, best first (`rows::filter_rows`: the start of the title, a title word, a keyword, the title, the RPM name, the summary, one letter wrong in words of five or more, the publisher and category) |
| `refreshOnStart` | bool, rw | setting |
| `licenceServer` | string, rw | licence service base URL; setting |

`catalogueModel`, `installedModel`, `featuredModel` and `recentModel` (the ten most recently updated, newest first) roles: `name` (RPM name), `title`, `summary`, `category`, `version` (catalogue build), `installState` (`not_installed`, `installed` or `update_available`), `installedVersion`, `licenceModel` (`free`, `one_off` or `subscription`), `licensed` (bool: a valid stored licence for the package's `app_id`), `publisher`, `iconPath` (the cached icon's local path, or empty), `featured` (bool) `isNew` (bool: `added` within the last 30 days), `updated` (`YYYY-MM-DD` of the newest changelog entry, else `added`) and `heroPath` (the first cached screenshot, the home page's banner, or empty). Rows are sorted by title.

`licenceModel` roles: `appId`, `title` (from the catalogue, falling back to `appId`), `plan`, `status` (`active`, `grace`, `expired`, `revoked` or `invalid`), `expiresText` (localised date, or empty), `licenceId`.

### Invokables

| Call | Returns | Backend |
| --- | --- | --- |
| `refresh()` | void | fetch `<store>/catalogue.json` and `Catalogue::parse` it, cache it and its images; also refreshes subscriptions that need it and the revocation list |
| `packageDetails(name)` | object | `{name, title, summary, description, category, version, installState, installedVersion, updateVersion, testedOn: [string], permissions: [string], sandboxed, licenceModel, licensed, purchaseUrl, spdx, sizeText, homepage, source, keelTier, publisher, iconPath, screenshotPaths: [string], added, updated, changelogJson, servicesJson, systemChangesJson}`. `servicesJson` and `systemChangesJson` are the catalogue's disclosures as JSON; `removable` is false for a package Reef shows as installed but did not install. `sizeText` is pre-formatted because Keel v1 has no `Format`. `keelTier` is the catalogue's `keel_tier` (`A`, `B`, `none`, `not-applicable`) or empty. `screenshotPaths` holds only the screenshots already cached; `added` is `YYYY-MM-DD` or empty; `updated` is the newest changelog entry's day (else `added`); `changelogJson` is the catalogue's `changelog` as a JSON string, `[{version, date, notes: [string]}]` newest first (`JSON.parse` it; a list of maps does not fit the bridge's values); `updateVersion` is the version PackageKit would update to (empty unless `installState` is `update_available`), which a cached catalogue can lag behind |
| `browse(kind, id)` | void | fills `browseModel`: `kind` `category` (that category's apps, by title), `collection` (in its order) or `all`; it follows refreshes until the next call |
| `appRow(name)` | object | the `catalogueModel` row of one app, `{}` when it is not shown: the home page's collection tiles (bind through `Reef.revision`) |
| `loadDetails(name)` | void | from the store index, fetches the app's details file (checked against the index's SHA-256, cached by hash) and merges it; `revision` changes when it is in. Nothing when the details are there (a `catalogue.json`, or a repository of up to 200 apps, whose details come with the index) |
| `checkLicenceToken(token)` | string | `""` if `Licence::verify_any_app` accepts the token, otherwise the error text |
| `licenceTokenApp(token)` | string | catalogue title (or app id) of a valid token |
| `addLicenceToken(token)` | string | `LicenceStore::save`; `""` or error text |
| `refreshLicences()` | void | `GET {licenceServer}/v1/claims/{code}` for each pending claim code (see "Buying"), then `GET {licenceServer}/v1/licences/{lid}/token` for each licence where `needs_refresh` is true, then `GET /v1/revocations` into `accept_revocations` |
| `removeLicence(appId)` | void | `LicenceStore::remove` |
| `buyUrl(name)` | string | the package's purchase URL with `claim=<code>` added (`claim_codes::purchase_url_with_claim`), after recording a new code as pending (`PendingClaims::create`); `""` for a free or unknown package, or with `lastError` set when the code cannot be recorded |
| `checkPurchases()` | void | `refreshLicences()` if a claim code is pending, at most every 10 seconds; after the running job when busy. The window calls it on becoming active |

### Buying

A paid app is bought on the web, so the licence has to come back to the phone by itself. Buy calls `buyUrl(name)`, which makes a claim code (128 bits from the OS random source, 32 lowercase hex characters), records it as pending in `$XDG_DATA_HOME/shipwright-reef/claims/<code>` (`{"app_id", "created_at"}`, mode 600, directory 700; at most 20, none older than 30 days), and gives the purchase URL with `claim=<code>` in its query; the page opens that URL and says the licence will follow. The checkout passes the code to the licence service with the order. Every licence refresh (at start with `refreshOnStart`, `refreshLicences()` on the licences page, and `checkPurchases()` when the user comes back from the browser) asks `GET {licenceServer}/v1/claims/{code}` for each pending code: a token (`{"token": …}`) is verified and stored like a pasted one and the code forgotten; 404 (not paid yet) keeps it; 410 (refunded or revoked) and 400 forget it; other failures keep it and are reported in `lastError`, with the code left out. Paid apps then get the token through the hand-off (`reef/licence/README.md`). Pasting a token stays as the fallback.

### Signals

Property change signals follow the usual `<property>Changed` convention.

## Checking

Syntax and lint:

```
cd apps/reef/ui
for f in $(find . -name '*.qml'); do /usr/lib/qt6/bin/qmlformat "$f" >/dev/null || echo "$f"; done
/usr/lib/qt6/bin/qmllint -I <keel build>/qml $(find . -name '*.qml')
```

qmllint reports `Shipwright.Reef` as unresolved (the CXX-Qt module is generated at build time) and `pageStack` as unqualified (ApplicationWindow's context property).
