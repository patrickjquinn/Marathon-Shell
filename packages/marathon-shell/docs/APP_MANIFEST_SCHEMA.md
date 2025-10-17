# Marathon App Manifest Schema

## Overview

Every Marathon app requires a `manifest.json` file in its root directory. This manifest defines the app's metadata, permissions, and deep link structure for system-wide search and navigation.

## Basic Structure

```json
{
  "id": "unique-app-id",
  "name": "App Display Name",
  "version": "1.0.0",
  "entryPoint": "MainApp.qml",
  "icon": "assets/icon.svg",
  "author": "Developer Name",
  "permissions": [],
  "minShellVersion": "1.0.0",
  "protected": false,
  "searchKeywords": [],
  "deepLinks": {}
}
```

## Required Fields

### `id` (string)
Unique identifier for your app. Use reverse-domain notation for third-party apps.

**Examples:**
- System apps: `"settings"`, `"calculator"`
- Third-party: `"com.example.myapp"`

### `name` (string)
Display name shown in the app grid and search results.

### `version` (string)
Semantic version number (`MAJOR.MINOR.PATCH`).

### `entryPoint` (string)
Path to the main QML file (relative to manifest).

**Example:** `"MyApp.qml"`

### `icon` (string)
Path to app icon (relative to manifest). Supports SVG, PNG.

**Example:** `"assets/icon.svg"`

### `author` (string)
Developer or organization name.

## Optional Fields

### `permissions` (array of strings)
System capabilities your app requires.

**Available permissions:**
- `"system"` - System-level access (protected apps only)
- `"network"` - Internet access
- `"location"` - GPS/location services
- `"storage"` - File system access
- `"camera"` - Camera access
- `"microphone"` - Microphone access
- `"contacts"` - Contacts database
- `"calendar"` - Calendar access

**Example:**
```json
"permissions": ["network", "location"]
```

### `minShellVersion` (string)
Minimum Marathon OS version required.

**Default:** `"1.0.0"`

### `protected` (boolean)
If `true`, app cannot be uninstalled by users. Reserved for system apps.

**Default:** `false`

---

## Deep Link Search (Core Feature)

Marathon apps support **first-class deep linking** for system-wide search and navigation.

### `searchKeywords` (array of strings)

Global keywords that help users discover your app in search.

**Example:**
```json
"searchKeywords": [
  "calculator",
  "math",
  "arithmetic",
  "numbers"
]
```

**Best practices:**
- Include synonyms and common misspellings
- Add category keywords (e.g., "productivity", "entertainment")
- Keep lowercase for consistency

### `deepLinks` (object)

Defines searchable pages/routes within your app. Each key is a route ID, and the value contains:

- `title` (string, required) - Display name in search results
- `description` (string, required) - Subtitle explaining the page
- `keywords` (array of strings, optional) - Additional search terms for this specific page

**Example:**
```json
"deepLinks": {
  "history": {
    "title": "Calculation History",
    "description": "View past calculations",
    "keywords": ["past", "previous", "log"]
  },
  "settings": {
    "title": "Calculator Settings",
    "description": "Configure calculator preferences",
    "keywords": ["preferences", "config", "options"]
  }
}
```

## How Deep Links Work

1. **Automatic Indexing:** The shell automatically indexes all deep links when your app is installed
2. **Search Integration:** Users can search for pages by title, description, or keywords
3. **Navigation:** When selected, the shell:
   - Launches your app (if not running)
   - Emits `NavigationRouter.deepLinkRequested(appId, route, params)` signal
   - Your app listens and navigates to the requested route

## Implementing Deep Link Handling in Your App

```qml
// In your MApp-based app
import MarathonOS.Shell

MApp {
    id: myApp
    appId: "myapp"
    
    Connections {
        target: typeof NavigationRouter !== 'undefined' ? NavigationRouter : null
        
        function onDeepLinkRequested(appId, route, params) {
            if (appId === myApp.appId) {
                Logger.info("MyApp", "Deep link requested: " + route)
                
                switch (route) {
                    case "history":
                        navigationStack.push(historyPageComponent)
                        break
                    case "settings":
                        navigationStack.push(settingsPageComponent)
                        break
                    default:
                        Logger.warning("MyApp", "Unknown route: " + route)
                }
            }
        }
    }
}
```

## Complete Example: Notes App

```json
{
  "id": "notes",
  "name": "Notes",
  "version": "1.0.0",
  "entryPoint": "NotesApp.qml",
  "icon": "assets/icon.svg",
  "author": "Marathon OS",
  "permissions": ["storage"],
  "minShellVersion": "1.0.0",
  "protected": false,
  "searchKeywords": [
    "notes",
    "text",
    "memo",
    "write",
    "document"
  ],
  "deepLinks": {
    "new": {
      "title": "New Note",
      "description": "Create a new note",
      "keywords": ["create", "add", "write"]
    },
    "recent": {
      "title": "Recent Notes",
      "description": "View recently edited notes",
      "keywords": ["history", "latest", "last"]
    },
    "favorites": {
      "title": "Favorite Notes",
      "description": "Starred and pinned notes",
      "keywords": ["starred", "pinned", "important"]
    },
    "search": {
      "title": "Search Notes",
      "description": "Find notes by content",
      "keywords": ["find", "lookup", "query"]
    }
  }
}
```

## Search Result Display

When users search, deep link results appear as:

- **Type badge:** "Page" (purple/violet badge)
- **Title:** From `deepLinks[route].title`
- **Subtitle:** From `deepLinks[route].description`
- **Icon:** Your app icon
- **Context:** Shows parent app name

## Testing Your Manifest

1. Install your app to `~/.local/share/marathon-apps/your-app/`
2. Restart the shell (or trigger rescan)
3. Open Hub search (swipe up from bottom)
4. Type keywords from your manifest
5. Verify deep links appear in results
6. Tap result and confirm navigation works

## Validation

The shell validates manifests during installation:

**Required fields missing:** App will not load
**Invalid JSON:** Installation fails
**Protected flag on third-party apps:** Ignored (requires system signature)

## Best Practices

1. **Keywords:** Include 5-15 total keywords across app + deep links
2. **Deep Links:** Add routes for all major pages/features
3. **Descriptions:** Keep under 50 characters for good UX
4. **Testing:** Test all deep link routes actually navigate correctly
5. **Updates:** Update `version` and `deepLinks` as you add features

## See Also

- Example apps: `/example-apps/calculator/manifest.json`
- System apps: `/apps/settings/manifest.json`
- MApp API: `/shell/qml/MarathonUI/Containers/MApp.qml`

