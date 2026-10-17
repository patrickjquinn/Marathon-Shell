# Marathon Permission System Guide

Marathon asks the user before an app reaches anything personal or the
system, in the shape of Android's runtime permissions.

## Overview

- **Declared, then disclosed**: an app lists its permissions in
  `manifest.json`. The installer shows every one before installing and
  records them in the install's receipt; an update that adds permissions
  waits for the user's consent. An app holds only permissions in its
  receipt (for Marathon's own apps, in their read-only manifest): one it
  never declared is denied without asking, and editing its manifest after
  installation changes nothing.
- **Asked once, at first launch**: the shell asks for every declared
  permission the user has not decided yet, in one prompt.
- **Restricted ones are refused openly**: `system` and `terminal` are held
  only by protected system apps. Any other app that declares one sees it
  listed as not allowed in that prompt.
- **Asked again on use**: if the prompt was dismissed, the first call that
  needs an undecided permission asks the user and fails with
  `AccessDenied: Permission requested: <name>`; retry after
  `PermissionGranted`.
- **Protected system apps** hold the permissions they declare without a
  prompt.
- **Revocable**: Settings → Apps → the app → Permissions.

## Available Permissions

Every name, and the words the install screen, the permission prompt and
Settings show, come from
[`schemas/marathon-permissions-v1.json`](../schemas/marathon-permissions-v1.json).
The file also marks each permission sensitive (the manifest must give a
reason in `permissionReasons`) or restricted (only Marathon's own apps may
declare it, and only its protected apps hold it). `phone` is an alias of
`telephony`; manifests use `telephony`. See
[APP_MANIFEST_SCHEMA.md](APP_MANIFEST_SCHEMA.md).

The sections below follow the vocabulary file; a unit test in
`crates/marathon-core-native/src/permissions.rs` fails when they drift.

### `network`

**Internet**: Connect to the internet and devices on your network.

The sandbox shares the host network namespace (without it the app has no
network at all), and `Network1`/`Modem1` reads are allowed.

### `location`

**Location**: See where the device is.

GeoClue answers the app's location requests, and `Location1` is open to it.

### `camera`

**Camera**: Take photos and record video.

### `microphone`

**Microphone**: Record audio.

Disclosure only: audio capture is not gated yet.

### `contacts`

**Contacts**: Read and change your contacts.

`Contacts1`.

### `calendar`

**Calendar**: Read and change your calendar events.

The Calendar app's events through `Settings1`.

### `storage`

**Your files**: Read and change your photos, music, videos, documents and downloads.

The sandbox binds Pictures, Music, Videos, Documents, Downloads and DCIM
read-write; `MediaLibrary1`; the app's own `<id>/` keys in shell settings.

### `notifications`

**Notifications**: Show notifications.

Disclosure only: notifications are not gated yet.

### `alarms`

**Alarms**: Set alarms and timers.

`Alarm1`.

### `telephony`

**Phone**: Make and answer calls and see your call history.

`Telephony1`, `CallHistory1` and `Sms1`.

### `sms`

**Messages**: Send and read SMS messages.

`Sms1`.

### `bluetooth`

**Bluetooth**: Connect to Bluetooth devices.

`Bluetooth1` reads.

### `sensors`

**Sensors**: Read the motion and light sensors.

`Sensor1`.

### `secret-service`

**Passwords**: Save and read passwords in your keyring.

The runner sets `MARATHON_PERM_SECRET_SERVICE=1`, which the mail sign-in
helper requires.

### `system`

**System settings**: Change Wi-Fi, Bluetooth, display, sound, security and other device settings.

Restricted. Writes through `Settings1`, `Security1`, `Bluetooth1`,
`Display1`, `Power1`, `Audio1`, `Network1`, `Modem1`, `Updates1`, `Dav1` and
`AppStore1`. `marathon-dev lint` rejects it in a third-party manifest.

### `terminal`

**Terminal**: Run commands with full access to the system.

Restricted. Disclosure only: it names what the Terminal app can do.

## Implementation Guide

### 1. Declare Permissions in Manifest

```json
{
  "id": "com.example.myapp",
  "name": "My App",
  "permissions": [
    "network",
    "location"
  ],
  "permissionReasons": {
    "location": "Shows the weather where you are"
  }
}
```

### 2. Request Permission at Runtime

```qml
import MarathonOS.Shell

Item {
    Component.onCompleted: {
        // Check if already granted
        if (!PermissionManager.hasPermission("myapp", "location")) {
            // Request permission
            PermissionManager.requestPermission("myapp", "location")
        } else {
            // Permission already granted
            startLocationTracking()
        }
    }
  
    // Listen for permission result
    Connections {
        target: PermissionManager
      
        function onPermissionGranted(appId, permission) {
            if (appId === "myapp" && permission === "location") {
                console.log("Location permission granted")
                startLocationTracking()
            }
        }
      
        function onPermissionDenied(appId, permission) {
            if (appId === "myapp" && permission === "location") {
                console.log("Location permission denied")
                showPermissionExplanation()
            }
        }
    }
}
```

### 3. Handle Permission Denial

Always provide fallback functionality:

```qml
function showPermissionExplanation() {
    // Show dialog explaining why permission is needed
    permissionDialog.open()
}

MModal {
    id: permissionDialog
    title: "Location Permission Required"
  
    MColumn {
        spacing: 15
      
        MText {
            text: "This app needs location access to show nearby places."
            wrapMode: Text.WordWrap
        }
      
        MButton {
            text: "Grant Permission"
            onClicked: {
                PermissionManager.requestPermission("myapp", "location")
                permissionDialog.close()
            }
        }
      
        MButton {
            text: "Continue Without Location"
            type: MButton.Text
            onClicked: {
                permissionDialog.close()
                showManualLocationEntry()
            }
        }
    }
}
```

### 4. Check Permission Before Use

Always check before accessing protected features:

```qml
function takePicture() {
    if (!PermissionManager.hasPermission("myapp", "camera")) {
        PermissionManager.requestPermission("myapp", "camera")
        return
    }
  
    // Permission granted, proceed
    camera.imageCapture.capture()
}
```

## Best Practices

### Request Context

 **Good**: Request permission when user initiates action
```qml
MButton {
    text: "Add Photo"
    onClicked: {
        // User wants to add photo, request camera
        if (!PermissionManager.hasPermission("myapp", "camera")) {
            PermissionManager.requestPermission("myapp", "camera")
        }
    }
}
```

 **Bad**: Request all permissions on app startup
```qml
Component.onCompleted: {
    // Don't do this!
    PermissionManager.requestPermission("myapp", "camera")
    PermissionManager.requestPermission("myapp", "location")
    PermissionManager.requestPermission("myapp", "contacts")
}
```

### Explain Why

Always explain why you need a permission:

```qml
MModal {
    title: "Camera Access"
  
    MText {
        text: "We need camera access to let you scan QR codes and take profile pictures."
        wrapMode: Text.WordWrap
    }
}
```

### Minimal Permissions

Only request permissions you actually need:

 **Good**: Weather app requesting `location` only
 **Bad**: Weather app requesting `camera`, `contacts`, `sms`

### Graceful Degradation

Provide functionality even without permission:

```qml
// Map app without location permission
if (!PermissionManager.hasPermission("myapp", "location")) {
    // Show map at default location
    // Let user manually search/navigate
} else {
    // Center map on user location
}
```

### One Permission at a Time

Don't overwhelm users with multiple permission requests:

```qml
//  Good: Request one, then after granted, request another if needed
function setupApp() {
    if (!PermissionManager.hasPermission("myapp", "location")) {
        PermissionManager.requestPermission("myapp", "location")
    }
}

Connections {
    target: PermissionManager
    function onPermissionGranted(appId, permission) {
        if (appId === "myapp" && permission === "location") {
            // Now request next permission if needed
            if (!PermissionManager.hasPermission("myapp", "network")) {
                PermissionManager.requestPermission("myapp", "network")
            }
        }
    }
}
```

## User Control

### Viewing Permissions

Users can view and manage app permissions in:
- Settings → Apps → [Your App] → Permissions

### Revoking Permissions

Users can revoke permissions at any time. Handle this gracefully:

```qml
// Periodically check if permission was revoked
Timer {
    interval: 5000  // Check every 5 seconds
    running: true
    repeat: true
  
    onTriggered: {
        if (isTrackingLocation && 
            !PermissionManager.hasPermission("myapp", "location")) {
            // Permission was revoked
            stopLocationTracking()
            showPermissionRevokedMessage()
        }
    }
}
```

## Security Considerations

### Don't Store Sensitive Data

Even with permission, don't store sensitive data unnecessarily:

```qml
//  Bad: Storing all contacts
var allContacts = ContactsManager.getAllContacts()
localStorage.setItem("contacts", JSON.stringify(allContacts))

//  Good: Only store what's needed
var selectedContact = ContactsManager.getContact(contactId)
// Use immediately, don't store
```

### Respect Privacy

- Only access data when actively needed
- Don't send data to servers without user consent
- Encrypt sensitive data in transit and at rest
- Provide privacy policy

### Permission Audit

Regular check what data your app accesses:

```qml
Component.onCompleted: {
    console.log("Granted permissions:")
    var permissions = ["network", "location", "camera"]
    for (var i = 0; i < permissions.length; i++) {
        if (PermissionManager.hasPermission("myapp", permissions[i])) {
            console.log("  -", permissions[i])
        }
    }
}
```

## Testing Permissions

### Development Testing

```bash
# Test with permission granted
# Grant via Settings app or permission dialog

# Test with permission denied
# Deny via Settings app

# Test revocation mid-use
# Grant, use feature, then revoke in Settings
```

### Automated Testing

```qml
// Mock PermissionManager for testing
property var mockPermissionManager: {
    "hasPermission": function(appId, perm) {
        return testPermissions[perm] === true
    }
}

property var testPermissions: {
    "location": true,
    "camera": false
}

// Run tests with different permission states
```

## Troubleshooting

### Permission Request Not Showing

- Check manifest.json includes permission
- Verify correct app ID
- Ensure not requesting "system" permission (restricted)

### Permission Check Always Returns False

- Verify permission was granted
- Check app ID matches manifest
- Look for typos in permission name

### User Never Sees Permission Dialog

- Might have already granted/denied
- Check Settings → Apps → [Your App] → Permissions
- User may have selected "Don't ask again"

## Reference

### PermissionManager API

```qml
// Check permission
bool hasPermission(string appId, string permission)

// Request permission (shows dialog if not yet decided)
void requestPermission(string appId, string permission)

// Set permission (used by system)
void setPermission(string appId, string permission, bool granted, bool remember)

// Revoke permission
void revokePermission(string appId, string permission)

// Get all permissions for app
QStringList getAppPermissions(string appId)

// Get permission description
string getPermissionDescription(string permission)

// Signals
signal permissionGranted(string appId, string permission)
signal permissionDenied(string appId, string permission)
signal permissionRevoked(string appId, string permission)
```

## Examples

See `apps/` directory for examples of apps using permissions:
- `apps/camera/` - Camera permission
- `apps/maps/` - Location permission
- `apps/phone/` - Telephony and contacts
- `apps/browser/` - Network permission

For more help, visit https://docs.marathonos.org/permissions

