# Marathon App Manifest

Every Marathon app has a `manifest.json` at its root. This page explains it;
two files define it:

- [`schemas/marathon-app-manifest-v1.schema.json`](../schemas/marathon-app-manifest-v1.schema.json),
  a JSON Schema (draft 2020-12) listing every field, its type and its
  allowed values. Where this page and the schema disagree, the schema is right.
- [`schemas/marathon-permissions-v1.json`](../schemas/marathon-permissions-v1.json),
  the permission vocabulary: each name, the wording the user sees, and
  whether it is *sensitive* or *restricted*. The shell's permission manager
  reads its names and wording from this file (through
  `MarathonManifest::permissions()` in libMarathonCore), so the prompt,
  Settings and the lint always agree.

Editors that support JSON Schema can validate a manifest as you type when it
names the schema with `"$schema"`.

## Lint

```bash
marathon-dev lint ./my-app                # an app directory
marathon-dev lint my-app-1.0.0.marathon   # a package
marathon-dev lint --system-app apps/*/    # Marathon's own apps
```

Each finding prints its rule, a JSON pointer into the manifest (or the file
concerned) and a message. Any error makes the command exit 1. ctest runs
`Lint_AppManifests` over every app in `apps/`, so CI fails when an in-tree
manifest drifts.

`--system-app` is for the apps in this repository. It allows the things a
third-party app may not have: a single-word id, `"protected": true` and the
restricted permissions.

| Rule | Checks |
|---|---|
| `manifest` | `manifest.json` exists and is JSON |
| `schema` | the manifest matches the schema: required fields, types, enums, no unknown keys |
| `id` | third-party ids are reverse-DNS (`com.example.app`) and not under `org.marathonos` |
| `protected` | only Marathon's own apps are protected |
| `permission` | restricted permissions (`system`, `terminal`) only in Marathon's own apps |
| `permission-reason` | every sensitive permission has a reason in `permissionReasons`, and every reason is for a requested permission |
| `files` | `entryPoint` and `icon` exist in the app |
| `tested-on` | each width in `testedOn.widths` is laid out by a test under `tests/` (`width: N`), and `keyboard` is only declared when a test sends key events |
| `id-cmake` | `add_marathon_app(...)` and `install_keel_actions(...)` in `CMakeLists.txt` use the app id, which names the install directory and the `org.marathonos.<id>` D-Bus name |
| `id-keel-actions` | the Keel Actions manifest's `appId` is `org.marathonos.<id>` |
| `id-directory` | with `--system-app`, the app's directory is named after its id |
| `id-package` | (warning) the package is named `<id>.marathon` or `<id>-<version>.marathon` |
| `package` | the package extracts (the installer's archive rules: no symlinks, no paths outside the app) |

The schema validation uses the [`jsonschema`](https://crates.io/crates/jsonschema)
crate; the rules are in `crates/marathon-core-native/src/manifest.rs`.

## Example

```json
{
  "manifestVersion": 1,
  "id": "com.example.notes",
  "name": "Notes",
  "version": "1.0.0",
  "entryPoint": "NotesApp.qml",
  "icon": "assets/icon.svg",
  "author": "Example Ltd",
  "permissions": ["network", "location"],
  "permissionReasons": {
    "location": "Tags each note with where you wrote it"
  },
  "categories": ["Productivity"],
  "searchKeywords": ["notes", "memo", "write"],
  "deepLinks": {
    "new": { "title": "New Note", "description": "Create a new note", "keywords": ["create", "add"] }
  },
  "testedOn": { "widths": [540, 720], "inputModes": ["touch", "keyboard"] },
  "dataLifecycle": { "appData": "remove", "cache": "remove" }
}
```

## Fields

Required: `manifestVersion`, `id`, `name`, `version`, `entryPoint`, `icon`,
`author`, `testedOn`, `dataLifecycle`.

| Field | Type | Meaning |
|---|---|---|
| `manifestVersion` | `1` | The manifest format. |
| `id` | string | The app id: the install directory, the Wayland `app_id`, the permission store key and the `org.marathonos.<id>` D-Bus name. Lowercase letters, digits, `_` and `-` in dot-separated parts, each starting with a letter. Third-party apps use reverse-DNS; single words are Marathon's. |
| `name` | string | Display name in the app grid and search. |
| `version` | string | Semantic version, `MAJOR.MINOR.PATCH`. |
| `entryPoint` | string | The main `.qml` file, relative to the manifest. |
| `icon` | string | An `.svg` or `.png`, relative to the manifest. |
| `author` | string | Developer or organisation. |
| `description` | string | One or two sentences. |
| `permissions` | array | Names from the permission vocabulary. |
| `permissionReasons` | object | Permission name → why the app needs it, shown to the user (10–300 characters). Required for every sensitive permission. |
| `minShellVersion` | string | Oldest shell the app runs on. |
| `protected` | boolean | A system app: cannot be uninstalled and holds its permissions without a prompt. Marathon's own apps only. |
| `toolkit` | `keel` \| `marathonui` | How the runner hosts the app. Default `keel`. |
| `categories` | array | `Communication`, `Productivity`, `Entertainment`, `Utility`, `System`. |
| `handlesUriSchemes` | array | URI schemes the app opens (`tel`, `mailto`, ...). |
| `defaultFor` | array | Default-app roles: `browser`, `dialer`, `messaging`, `email`, `camera`, `gallery`, `music`, `video`, `files`. |
| `searchKeywords` | array | Extra search terms for the app. |
| `deepLinks` | object | Route → `{ title, description, keywords }`, indexed by search (below). |
| `backgroundCapabilities` | array | Categories the app may hold `AppLifecycle1.BeginBackgroundTask` for: `active-call`, `active-navigation`, `audio-playback`, `countdown-timer`, `download`, `location-tracking`, `periodic-sync`, `recording`. |
| `requiresQtModules` | array | `webengine`: the runner loads QtWebEngine before the app starts. |
| `chromiumFlags` | string | Space-separated Chromium switches over the device default. Needs `requiresQtModules: ["webengine"]`. |
| `testedOn` | object | Below. |
| `dataLifecycle` | object | Below. |

### Permissions

The vocabulary file lists every permission. Two flags matter to a manifest:

- **sensitive**: the app must say why it asks, in `permissionReasons`. The
  reason is the app's own words next to the system's description of the
  permission, as iOS shows an app's usage description.
- **restricted**: only Marathon's own apps may ask (`system`, `terminal`).

`storage` grants both the media folders (Pictures, Music, Videos, Documents,
Downloads, DCIM) and access to the app's own keys in shell settings
(`Settings.get("<id>/...")`), so an app that only keeps settings there still
needs it.

### testedOn

```json
"testedOn": { "widths": [540, 720], "inputModes": ["touch", "keyboard"] }
```

- `widths`: window widths, in pixels, that the app's tests lay it out at
  (540 is the phone canvas the QML suites use, 720 the square and phone
  panels). The lint looks for each as `width: N` under `tests/`.
- `inputModes`: `touch` (required), `keyboard` (a physical keyboard, as on
  the HackberryPi; a test must send key events), `pointer`.

### dataLifecycle

What uninstalling the app does to its data, after Luma's `[lifecycle]` table.

| Key | Values | Covers |
|---|---|---|
| `appData` | `remove` \| `keep` | `$XDG_DATA_HOME/marathon-apps/<id>`, `$XDG_CONFIG_HOME/marathon-apps/<id>`, the app's dconf keys under `/apps/<id>/` and its `<id>/` keys in shell settings |
| `cache` | `remove` | `$XDG_CACHE_HOME/marathon-apps/<id>` |
| `secrets` | `remove` \| `keep` | the app's Secret Service items; declared exactly when the app requests `secret-service` |
| `userFiles` | `preserve` | files the app wrote to the media folders, which are never deleted with the app; only with `storage` |

The uninstaller does not act on this declaration yet; it removes the app's
install directory only.

## Deep links

`deepLinks` lists pages search can open. Each key is a route; the value has
a `title` and `description` (required) and optional `keywords`.

```json
"deepLinks": {
  "wifi": {
    "title": "WiFi Settings",
    "description": "Manage wireless network connections",
    "keywords": ["network", "internet", "wireless"]
  }
}
```

The shell indexes them when it scans the app. When the user picks one, the
shell launches the app with the route in `MARATHON_APP_ROUTE`, or, if it is
running, emits `NavigationRouter.deepLinkRequested(appId, route, params)`.
`apps/settings/SettingsApp.qml` handles both.

## What else checks the manifest

- The scanner (`MarathonAppScanner`) skips a manifest without `id`, `name`
  or `entryPoint`.
- The packager and installer require `id`, `name`, `version`, `entryPoint`
  and `icon`, and that the entry point exists.

Neither runs the full contract; `marathon-dev lint` does.

The installer also shows each declared permission to the user in words, refuses
a package that declares one it can't describe, and holds an update that adds
permissions until the user agrees (docs/CODE_SIGNING_GUIDE.md).

## See also

- `apps/template/manifest.json`, `apps/settings/manifest.json`
- [PERMISSION_GUIDE.md](PERMISSION_GUIDE.md)
- [PUBLISHING_GUIDE.md](PUBLISHING_GUIDE.md)
