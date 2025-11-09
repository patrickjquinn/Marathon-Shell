# Marathon App Development Guide

Welcome to Marathon OS app development! This guide will help you build high-quality apps for the Marathon mobile platform.

## Table of Contents

- [Quick Start](#quick-start)
- [Development Environment](#development-environment)
- [App Structure](#app-structure)
- [MarathonUI Components](#marathonui-components)
- [System APIs](#system-apis)
- [Permissions](#permissions)
- [Testing](#testing)
- [Packaging & Distribution](#packaging--distribution)

## Quick Start

### Create Your First App

```bash
# Install marathon-dev tool
cd /path/to/Marathon-Shell
cmake -B build
cmake --build build
sudo cmake --install build

# Create a new app
marathon-dev init my-awesome-app
cd my-awesome-app

# Edit your app
$EDITOR MyawesomeApp.qml

# Test your app
marathon-dev validate .

# Package your app
marathon-dev package .
```

Your app is now ready to install!

## Development Environment

### Prerequisites

- Qt 6.5 or later
- QML development tools
- Text editor or IDE (VS Code, Qt Creator, etc.)
- Marathon Shell (for testing)

### Recommended Setup

1. **VS Code** with QML extension
2. **Qt Creator** for visual editing
3. **qmllint** for code validation

### Hot Reload Development

While developing, you can test your app live in Marathon Shell:

```bash
# Run Marathon Shell in debug mode
MARATHON_DEBUG=1 ./run.sh

# Your app will auto-reload on file changes
```

## App Structure

### Minimal App Structure

```
my-app/
├── manifest.json       # App metadata (required)
├── MyApp.qml          # Main entry point (required)
├── assets/
│   └── icon.svg       # App icon (required)
├── pages/             # App pages (optional)
├── components/        # Reusable components (optional)
└── qmldir             # QML module definition (recommended)
```

### manifest.json

```json
{
  "id": "com.example.myapp",
  "name": "My Awesome App",
  "version": "1.0.0",
  "entryPoint": "MyApp.qml",
  "icon": "assets/icon.svg",
  "author": "Your Name",
  "permissions": ["network", "storage"],
  "minShellVersion": "1.0.0",
  "protected": false,
  "searchKeywords": ["awesome", "utility"],
  "categories": ["Productivity"]
}
```

### Main App File (MyApp.qml)

```qml
import QtQuick
import QtQuick.Controls
import MarathonUI.Core
import MarathonUI.Controls
import MarathonUI.Navigation
import MarathonOS.Shell

MApplicationWindow {
    id: root
    title: "My Awesome App"
    
    initialPage: mainPage
    
    Component {
        id: mainPage
        
        MPage {
            title: "Home"
            
            actions: [
                MAction {
                    icon: "settings"
                    text: "Settings"
                    onTriggered: root.push(settingsPage)
                }
            ]
            
            MColumn {
                anchors.centerIn: parent
                spacing: 20
                
                MText {
                    text: "Welcome to My App!"
                    type: MText.Heading
                }
                
                MButton {
                    text: "Click Me"
                    onClicked: {
                        console.log("Button clicked!")
                    }
                }
            }
        }
    }
    
    Component {
        id: settingsPage
        
        MPage {
            title: "Settings"
            showBackButton: true
            
            // Settings content here
        }
    }
}
```

## MarathonUI Components

Marathon provides a comprehensive UI library optimized for mobile.

### Layout Components

- **MColumn** - Vertical layout
- **MRow** - Horizontal layout
- **MGrid** - Grid layout
- **MStack** - Layered layout

### Display Components

- **MText** - Styled text (Heading, Title, Subtitle, Body, Caption)
- **MIcon** - Material Design icons
- **MImage** - Optimized images
- **MCard** - Card container

### Input Components

- **MButton** - Button (Filled, Outlined, Text)
- **MTextInput** - Text input field
- **MSwitch** - Toggle switch
- **MSlider** - Value slider
- **MCheckbox** - Checkbox
- **MRadioButton** - Radio button

### Navigation Components

- **MPage** - Page container
- **MApplicationWindow** - App window with navigation
- **MDrawer** - Side drawer navigation
- **MBottomBar** - Bottom navigation bar

### List Components

- **MListView** - Scrollable list
- **MListItem** - List item
- **MGrid** - Grid view

### Feedback Components

- **MModal** - Modal dialog
- **MSnackbar** - Toast notification
- **MProgressBar** - Progress indicator
- **MLoadingSpinner** - Loading animation

### Example Usage

```qml
MPage {
    title: "Example Page"
    
    MColumn {
        anchors.fill: parent
        padding: 20
        spacing: 15
        
        MCard {
            MColumn {
                padding: 15
                spacing: 10
                
                MText {
                    text: "Card Title"
                    type: MText.Subtitle
                }
                
                MText {
                    text: "Card content goes here"
                }
            }
        }
        
        MButton {
            text: "Primary Action"
            type: MButton.Filled
            onClicked: doSomething()
        }
        
        MTextInput {
            placeholderText: "Enter text..."
            onTextChanged: console.log(text)
        }
    }
}
```

## System APIs

### Available Services

Marathon exposes several system services via QML context properties:

- **AppRegistry** - App management
- **NetworkManager** - Network connectivity
- **PowerManager** - Battery and power
- **DisplayManager** - Screen settings
- **AudioManager** - Audio control
- **TelephonyService** - Phone calls
- **SMSService** - Text messages
- **ContactsManager** - Contacts access
- **LocationService** - GPS location
- **StorageManager** - File system
- **PermissionManager** - App permissions

### Network Access

```qml
import MarathonOS.Shell

Item {
    Component.onCompleted: {
        // Check network status
        if (NetworkManager.wifiConnected) {
            console.log("Connected to:", NetworkManager.wifiSSID)
        }
        
        // Listen for changes
        NetworkManager.wifiConnectedChanged.connect(() => {
            if (NetworkManager.wifiConnected) {
                loadData()
            }
        })
    }
    
    function loadData() {
        // Use QML XmlHttpRequest or Qt.createQmlObject for REST APIs
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "https://api.example.com/data")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                var data = JSON.parse(xhr.responseText)
                // Process data
            }
        }
        xhr.send()
    }
}
```

### Contacts Access

```qml
import MarathonOS.Shell

Item {
    Component.onCompleted: {
        // Request permission first
        PermissionManager.requestPermission("myapp", "contacts")
    }
    
    Connections {
        target: PermissionManager
        
        function onPermissionGranted(appId, permission) {
            if (appId === "myapp" && permission === "contacts") {
                loadContacts()
            }
        }
    }
    
    function loadContacts() {
        var contacts = ContactsManager.getAllContacts()
        for (var i = 0; i < contacts.length; i++) {
            console.log(contacts[i].name, contacts[i].phone)
        }
    }
}
```

### Location Services

```qml
import MarathonOS.Shell

Item {
    Component.onCompleted: {
        // Request location permission
        PermissionManager.requestPermission("myapp", "location")
    }
    
    Connections {
        target: LocationService
        
        function onPositionChanged() {
            console.log("Lat:", LocationService.latitude)
            console.log("Lon:", LocationService.longitude)
        }
    }
    
    function startTracking() {
        if (PermissionManager.hasPermission("myapp", "location")) {
            LocationService.startUpdates()
        }
    }
}
```

## Permissions

### Available Permissions

- **network** - Internet and network access
- **location** - GPS and location services
- **camera** - Camera access
- **microphone** - Microphone access
- **contacts** - Read/write contacts
- **calendar** - Calendar events
- **storage** - File system access
- **notifications** - Show notifications
- **telephony** - Phone calls
- **sms** - Text messages
- **bluetooth** - Bluetooth devices

### Requesting Permissions

```qml
// In your main app file
Component.onCompleted: {
    // Check if permission is already granted
    if (PermissionManager.hasPermission("myapp", "camera")) {
        initializeCamera()
    } else {
        // Request permission (will show system dialog)
        PermissionManager.requestPermission("myapp", "camera")
    }
}

Connections {
    target: PermissionManager
    
    function onPermissionGranted(appId, permission) {
        if (appId === "myapp" && permission === "camera") {
            initializeCamera()
        }
    }
    
    function onPermissionDenied(appId, permission) {
        if (appId === "myapp" && permission === "camera") {
            showPermissionDeniedMessage()
        }
    }
}
```

### Best Practices

1. **Request permissions at runtime**, not on startup
2. **Explain why** you need the permission
3. **Handle denial gracefully**
4. **Request minimal permissions**

## Testing

### Validate Your App

```bash
# Check manifest and QML syntax
marathon-dev validate ./my-app

# Check for common issues
qmllint MyApp.qml
```

### Test on Device

```bash
# Install your app locally
marathon-dev install ./my-app

# Or install from package
marathon-dev install my-app.marathon
```

### Debug Logging

```qml
// Use console.log for debugging
console.log("Debug:", value)
console.warn("Warning:", message)
console.error("Error:", error)
```

View logs:

```bash
# Run with debug mode
MARATHON_DEBUG=1 ./run.sh

# Or check journal
journalctl -f | grep marathon
```

## Packaging & Distribution

### Create Package

```bash
# Package your app
marathon-dev package ./my-app

# This creates: my-app.marathon
```

### Sign Your Package

```bash
# Generate GPG key (first time only)
gpg --full-generate-key

# Sign your app
marathon-dev sign ./my-app [your-key-id]

# This creates: SIGNATURE.txt in your app directory
```

### Submit to App Store

1. Create account at apps.marathonos.org
2. Upload your .marathon package
3. Fill in app details
4. Submit for review

### Update Your App

1. Increment version in manifest.json
2. Package and sign again
3. Submit update to app store

## Best Practices

### Performance

1. **Lazy load** pages and components
2. **Cache data** when appropriate
3. **Use async operations** for network/file I/O
4. **Optimize images** (use SVG when possible)
5. **Minimize JavaScript** in QML

### UX/UI

1. **Follow Marathon design guidelines**
2. **Support gestures** (swipe back, etc.)
3. **Provide feedback** for actions
4. **Handle errors gracefully**
5. **Support both portrait and landscape**

### Security

1. **Validate user input**
2. **Use HTTPS** for network requests
3. **Don't store sensitive data** in plain text
4. **Respect user privacy**
5. **Handle permissions properly**

## Resources

- [App Manifest Schema](./APP_MANIFEST_SCHEMA.md)
- [Publishing Guide](./PUBLISHING_GUIDE.md)
- [Permission Guide](./PERMISSION_GUIDE.md)
- [MarathonUI Components Reference](./MARATHONUI_REFERENCE.md)
- [Example Apps](../apps/)

## Support

- **Forum**: forum.marathonos.org
- **Documentation**: docs.marathonos.org
- **Bug Reports**: github.com/marathonos/marathon-shell/issues

Happy coding! 

