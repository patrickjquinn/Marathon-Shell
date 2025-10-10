# Marathon Shell - BlackBerry 10 Implementation

## ✅ Complete BlackBerry 10 Experience

### Reusable Components

#### MarathonToggle (`shell/qml/components/MarathonToggle.qml`)
- Authentic BB10-style toggle switches
- Teal accent color when active
- Smooth animations
- Used throughout Quick Settings

#### MarathonCard (`shell/qml/components/MarathonCard.qml`)
- White card with rounded corners
- Subtle shadow effect
- Border styling
- Reusable container

#### MarathonListItem (`shell/qml/components/MarathonListItem.qml`)
- Notification/inbox list items
- Icon with colored background
- Title, subtitle, and timestamp
- Delete button with icon
- Press feedback
- Separator line
- Used in Hub/Notifications

### Stores (State Management)

#### AppStore (`shell/qml/stores/AppStore.qml`)
**Real Logic Implemented:**
- `launchApp(appId)` - Launches app and adds to running list
- `closeApp(appId)` - Removes from running list
- `switchToApp(appId)` - Changes current app
- `closeAllApps()` - Clears all running apps
- `runningApps` - Array tracking all running applications
- `currentApp` - Currently focused app ID
- Signals: `appLaunched`, `appClosed`, `appSwitched`

#### NotificationStore (`shell/qml/stores/NotificationStore.qml`)
**Real Logic Implemented:**
- `addNotification(notification)` - Adds new notification
- `removeNotification(id)` - Deletes notification
- `markAsRead(id)` - Marks notification as read
- `clearAll()` - Removes all notifications
- `notifications` - Array of notification objects
- `unreadCount` - Computed count of unread notifications
- Signals: `notificationAdded`, `notificationRemoved`, `notificationRead`

**Notification Data Structure:**
```javascript
{
    id: "unique-id",
    type: "email" | "system" | "message",
    title: "Title",
    subtitle: "Description",
    time: "9:36 PM",
    date: "Tuesday, September 2, 2014",
    icon: "qrc:/images/messages.svg",
    read: false
}
```

### Active Frames (Task Switcher)

**MarathonTaskSwitcher** (`shell/qml/components/MarathonTaskSwitcher.qml`)
- Grid layout showing all running apps
- App cards with:
  - App icon (96x96)
  - App name
  - Red X button to close (top-right)
- "Close All" button in header
- Click card to switch to app
- Click X to close app
- Empty state message when no apps running
- Connected to `AppStore.runningApps`

**Functionality:**
- When app launched → Added to `AppStore.runningApps`
- Shows in Task Switcher immediately
- X button calls `AppStore.closeApp(id)`
- Card click calls `AppStore.switchToApp(id)` and closes switcher
- Close All calls `AppStore.closeAllApps()`

### BlackBerry Hub

**MarathonHub** (`shell/qml/components/MarathonHub.qml`)
- White background (authentic BB10 style)
- Header with "BLACKBERRY HUB" title
- Search button in header
- Unified inbox showing all notifications
- Grouped by date (section headers)
- List items with:
  - Icon with accent color
  - Title and subtitle
  - Timestamp
  - Delete button
- Connected to `NotificationStore.notifications`

**Functionality:**
- Click notification → Marks as read
- Click delete → Removes notification
- Scrollable list
- Date grouping

### Peek & Flow

**MarathonPeek** (`shell/qml/components/MarathonPeek.qml`)
- Signature BB10 gesture
- Swipe from left edge to peek
- Shows notification indicators when closed (up to 3)
- Displays Hub when fully opened
- Smooth progress animation
- Overlay darkening effect
- Snap to open/closed based on threshold

**Functionality:**
- Drag from left edge (30px trigger zone)
- `peekProgress` tracks 0-1 drag amount
- Indicators show `NotificationStore.unreadCount`
- Opens Hub component
- Click overlay to close
- All notifications accessible from peek

### Wiring Summary

#### App Launch Flow:
1. User taps app icon in `MarathonAppGrid`
2. `AppStore.launchApp(appId)` is called
3. App is added to `AppStore.runningApps` array
4. `appLaunched` signal emitted
5. `MarathonShell` listens and sets `showTaskSwitcher = true`
6. App appears in Active Frames

#### App Close Flow:
1. User taps X button in Task Switcher
2. `AppStore.closeApp(appId)` is called
3. App is removed from `runningApps` array
4. `appClosed` signal emitted
5. UI updates automatically (array binding)

#### Notification Flow:
1. Notifications stored in `NotificationStore.notifications`
2. Hub displays via ListView binding
3. Click notification → `markAsRead(id)` called
4. Click delete → `removeNotification(id)` called
5. `unreadCount` updates automatically
6. Peek indicators reflect unread count

### Testing Checklist

✅ **App Launching:**
- Tap any app icon
- Task Switcher appears
- App shown in Active Frames grid

✅ **App Closing:**
- Open Task Switcher (swipe up from bottom)
- Click X on any app card
- App disappears from list

✅ **App Switching:**
- Open Task Switcher
- Click on any app card
- Switches to app and closes switcher

✅ **Notifications:**
- Swipe from left (Peek & Flow)
- See notification indicators
- Open Hub fully
- Click notification (marks as read)
- Click delete button (removes notification)

✅ **Close All Apps:**
- Open Task Switcher with apps running
- Click "Close All" button
- All apps removed
- Empty state message appears

### Code Quality

- **DRY Principles:** Reusable components (MarathonToggle, MarathonCard, MarathonListItem)
- **Separation of Concerns:** Logic in stores, UI in components
- **Real State Management:** No mock data, actual JavaScript logic
- **Signal/Slot Pattern:** Proper Qt event handling
- **Property Bindings:** Reactive UI updates
- **Console Logging:** Extensive debugging output

### Next Steps (Future)

- System integration (actual app processes)
- Virtual keyboard
- Universal search
- Balance (work/personal profiles)
- Advanced animations/effects
- Real notification system integration
- Compositor integration

## How to Run

```bash
./run.sh
```

Or manually:
```bash
mkdir -p build
cmake -S . -B build
cmake --build build
./build/shell/marathon-shell
```

## Default PIN
`147147`

---
**Built with strong, reusable components and fully wired logic! 🚀**

