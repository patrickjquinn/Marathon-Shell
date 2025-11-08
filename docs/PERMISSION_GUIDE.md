# Marathon Permission System Guide

Marathon uses a runtime permission system to protect user privacy and security.

## Overview

- **Runtime Permissions**: Users grant/deny at runtime, not install time
- **Granular Control**: Individual permissions per app
- **Revocable**: Users can revoke permissions anytime
- **Transparent**: Clear explanation of what each permission does

## Available Permissions

### network
**Access the internet and make network connections**

Use for:
- HTTP/HTTPS requests
- WebSocket connections
- API calls
- Downloading content

Example:
```qml
// Check permission
if (PermissionManager.hasPermission("myapp", "network")) {
    fetchDataFromAPI()
}
```

### location
**Access device GPS and location services**

Use for:
- Maps and navigation
- Location-based services
- Geotagging
- Weather based on location

Provides:
- Latitude/longitude
- Accuracy
- Altitude
- Speed

### camera
**Access device camera to capture photos and videos**

Use for:
- Taking photos
- Recording videos
- QR code scanning
- AR applications

### microphone
**Record audio using the device microphone**

Use for:
- Voice recording
- Voice notes
- Voice calls
- Audio analysis

### contacts
**Read and write device contacts**

Use for:
- Contact picker
- Messaging apps
- Social features
- Contact backup

Operations:
- Read all contacts
- Search contacts
- Add new contacts
- Update existing contacts
- Delete contacts

### calendar
**Read and write calendar events**

Use for:
- Event management
- Scheduling
- Reminders
- Meeting coordination

### storage
**Read and write files on device storage**

Use for:
- File management
- Document editing
- Media libraries
- Data export/import

Scope:
- Documents folder
- Downloads folder
- Pictures folder
- App-specific storage

### notifications
**Show notifications to the user**

Use for:
- Alerts
- Reminders
- Status updates
- Background updates

### telephony
**Make and receive phone calls**

Use for:
- Dialer apps
- VoIP applications
- Call management

### sms
**Send and receive text messages**

Use for:
- Messaging apps
- SMS verification
- Two-factor authentication

### bluetooth
**Connect to Bluetooth devices**

Use for:
- Wireless headphones
- Fitness trackers
- IoT devices
- File transfer

### system
**Access system-level features (restricted)**

Only for:
- System applications
- Launcher apps
- Settings apps

This permission is only granted to apps signed by Marathon OS.

## Implementation Guide

### 1. Declare Permissions in Manifest

```json
{
  "id": "com.example.myapp",
  "name": "My App",
  "permissions": [
    "network",
    "location"
  ]
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

✅ **Good**: Request permission when user initiates action
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

❌ **Bad**: Request all permissions on app startup
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

✅ **Good**: Weather app requesting `location` only
❌ **Bad**: Weather app requesting `camera`, `contacts`, `sms`

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
// ✅ Good: Request one, then after granted, request another if needed
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
// ❌ Bad: Storing all contacts
var allContacts = ContactsManager.getAllContacts()
localStorage.setItem("contacts", JSON.stringify(allContacts))

// ✅ Good: Only store what's needed
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

