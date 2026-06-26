pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// DS Settings · screens-apps-1.jsx:SettingsApp (23 · Settings).
//
// Strict rule: NO placeholder strings. Every visible value is bound to
// a real service. Where a service doesn't yet exist (account/profile,
// Marathon Intelligence, named Focus modes, Wallet & Passkeys), the row
// is omitted rather than faked. When the service ships, the row comes
// back. Shipping a fake "On-device · 3.2 GB model" reads as a broken
// demo, not a polished OS.
//
// Concretely omitted (vs the JSX reference):
//   • Profile hero card — no AccountService / UserService exists.
//     SessionStore tracks lock state, not identity.
//   • MARATHON INTELLIGENCE section — no LLMService / on-device model
//     manager exists. The "On" value and "3.2 GB model" subtitle would
//     be lies.
//   • Focus row — only the boolean DnD toggle exists (kept in DEVICE);
//     no named-mode Focus service with active-until timestamps.
//   • Wallet & Passkeys — no credential storage / FIDO2 service exists.
//
// What stays — every row binds to a real store:
//   SystemStatusStore  wifiNetwork · bluetoothDevices · storageUsed/Total
//   SystemControlStore isBluetoothOn · isAirplaneModeOn · isDndMode · brightness · volume
//   SecurityManagerCpp hasQuickPIN · fingerprintAvailable
//   SettingsManagerCpp hiddenApps · appSortOrder · filterMobileFriendlyApps ·
//                      searchNativeApps · showNotificationBadges · showFrequentApps
//   NotificationServiceCpp / SystemStatusStore notificationCount
Page {
    id: mainPage

    property string pageName: "main"

    signal navigateToPage(string page)
    signal requestClose

    // Derived summaries are property bindings, not functions — Qt's
    // binding analyzer cannot see through function calls to track
    // dependencies, so a `value: foo()` binding evaluates exactly once
    // and never refreshes when the underlying store changes.
    //
    // First connected bluetooth device name, if any. Falls back to
    // "On"/"Off" (still real state) when no device is connected.
    // SystemStatusStore is a sandboxed IPC client in the runner — older
    // builds of the client don't expose bluetoothDevices/storageTotal/
    // isCharging, which threw "Cannot read property 'length' of undefined"
    // at every render and broke the page. Guard each access.
    readonly property string btConnectedName: {
        const devs = SystemStatusStore.bluetoothDevices || [];
        for (let i = 0; i < devs.length; i++) {
            const d = devs[i];
            if (d && d.connected)
                return d.name || d.alias || "";
        }
        return "";
    }
    readonly property string btSummary: !SystemControlStore.isBluetoothOn ? "Off" : (btConnectedName !== "" ? btConnectedName : "On")

    readonly property string storageSummary: {
        const t = SystemStatusStore.storageTotal || 0;
        if (!(t > 0))
            return "";
        const used = SystemStatusStore.storageUsed || 0;
        const free = Math.max(0, t - used);
        return free.toFixed(0) + " GB free";
    }

    readonly property string batterySummary: {
        const lvl = SystemStatusStore.batteryLevel;
        if (typeof lvl !== "number" || lvl < 0)
            return "";
        return SystemStatusStore.isCharging ? lvl + "% · Charging" : lvl + "%";
    }

    readonly property string securitySummary: {
        const pin = SecurityManagerCpp.hasQuickPIN ? "PIN set" : "No PIN";
        return SecurityManagerCpp.fingerprintAvailable ? pin + " · Fingerprint" : pin;
    }

    Component.onCompleted: {
        Logger.info("SettingsMainPage", "Initialized");
    }

    Flickable {
        id: scrollView

        anchors.fill: parent
        contentHeight: settingsContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: 1500
        maximumFlickVelocity: 2500

        Column {
            id: settingsContent

            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24

            // ── Title + search ─────────────────────────────────────
            // DS Title 1 — 34/200 with -0.8 tracking.
            Item {
                width: parent.width - 48
                height: titleText.implicitHeight

                Text {
                    id: titleText
                    text: "Settings"
                    color: MColors.textPrimary
                    font.pixelSize: MTypography.sizeTitle1
                    font.weight: MTypography.weightExtraLight
                    font.letterSpacing: MTypography.trackingTitle1
                    font.family: MTypography.fontFamily
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Icon {
                    name: "search"
                    size: 22
                    color: MColors.textSecondary
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ── CONNECTIVITY ───────────────────────────────────────
            MSection {
                title: "Connectivity"
                eyebrow: true
                width: parent.width - 48

                MSettingsListItem {
                    title: "Wi-Fi"
                    iconName: "wifi"
                    value: SystemStatusStore.wifiConnected ? (SystemStatusStore.wifiNetwork || "On") : "Off"
                    onSettingClicked: mainPage.navigateToPage("wifi")
                }

                MSettingsListItem {
                    title: "Bluetooth"
                    iconName: "bluetooth"
                    value: mainPage.btSummary
                    onSettingClicked: mainPage.navigateToPage("bluetooth")
                }

                MSettingsListItem {
                    title: "Mobile Network"
                    iconName: "signal"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("cellular")
                }

                MSettingsListItem {
                    title: "Airplane Mode"
                    iconName: "plane"
                    showToggle: true
                    toggleValue: SystemControlStore.isAirplaneModeOn
                    onToggleChanged: value => SystemControlStore.toggleAirplaneMode()
                }
            }

            // ── DEVICE ─────────────────────────────────────────────
            MSection {
                title: "Device"
                eyebrow: true
                width: parent.width - 48

                MSettingsListItem {
                    title: "Display & Brightness"
                    iconName: "sun"
                    value: SystemControlStore.brightness + "%"
                    onSettingClicked: mainPage.navigateToPage("display")
                }

                MSettingsListItem {
                    title: "Sound"
                    iconName: "volume-2"
                    value: SystemControlStore.volume + "%"
                    onSettingClicked: mainPage.navigateToPage("sound")
                }

                MSettingsListItem {
                    title: "Notifications"
                    iconName: "bell"
                    value: (typeof SystemStatusStore !== "undefined" && SystemStatusStore && SystemStatusStore.notificationCount > 0) ? SystemStatusStore.notificationCount + " unread" : ""
                    onSettingClicked: mainPage.navigateToPage("notifications")
                }

                MSettingsListItem {
                    title: "Do Not Disturb"
                    iconName: "moon"
                    showToggle: true
                    toggleValue: SystemControlStore.isDndMode
                    onToggleChanged: value => SystemControlStore.toggleDndMode()
                }

                MSettingsListItem {
                    title: "Storage"
                    iconName: "hard-drive"
                    value: mainPage.storageSummary
                    onSettingClicked: mainPage.navigateToPage("storage")
                }

                MSettingsListItem {
                    title: "Battery"
                    iconName: "battery"
                    value: mainPage.batterySummary
                    onSettingClicked: mainPage.navigateToPage("battery")
                }
            }

            // ── SECURITY & PRIVACY ─────────────────────────────────
            MSection {
                title: "Security & Privacy"
                eyebrow: true
                width: parent.width - 48

                MSettingsListItem {
                    title: "Security"
                    subtitle: mainPage.securitySummary
                    iconName: "shield"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("security")
                }
            }

            // ── SYSTEM ─────────────────────────────────────────────
            MSection {
                title: "System"
                eyebrow: true
                width: parent.width - 48

                MSettingsListItem {
                    title: "About"
                    iconName: "info"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("about")
                }

                MSettingsListItem {
                    title: "Software Updates"
                    iconName: "download"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("updates")
                }

                MSettingsListItem {
                    title: "Keyboard"
                    iconName: "keyboard"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("keyboard")
                }

                MSettingsListItem {
                    title: "App Manager"
                    iconName: "package"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("appmanager")
                }

                MSettingsListItem {
                    title: "Accounts"
                    iconName: "users"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("accounts")
                }

                MSettingsListItem {
                    title: "Terminal"
                    iconName: "square-terminal"
                    showChevron: true
                    onSettingClicked: AppLifecycleManager.launchAppWithRoute("terminal", "", "{}")
                }
            }

            // ── APPS & LAYOUT ──────────────────────────────────────
            MSection {
                title: "Apps & Layout"
                eyebrow: true
                width: parent.width - 48

                MSettingsListItem {
                    title: "Quick Settings"
                    iconName: "settings-2"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("quicksettings")
                }

                MSettingsListItem {
                    title: "Hidden Apps"
                    iconName: "eye-off"
                    value: SettingsManagerCpp.hiddenApps.length > 0 ? SettingsManagerCpp.hiddenApps.length + " hidden" : ""
                    onSettingClicked: mainPage.navigateToPage("hiddenapps")
                }

                MSettingsListItem {
                    title: "Default Apps"
                    iconName: "star"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("defaultapps")
                }

                MSettingsListItem {
                    title: "App Sorting & Layout"
                    iconName: "layout-grid"
                    value: {
                        const o = SettingsManagerCpp.appSortOrder;
                        return o === "alphabetical" ? "A–Z" : o === "frequent" ? "Most Used" : o === "recent" ? "Recent" : "Custom";
                    }
                    onSettingClicked: mainPage.navigateToPage("appsort")
                }

                MSettingsListItem {
                    title: "Filter Non-Mobile Apps"
                    iconName: "smartphone"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.filterMobileFriendlyApps
                    onToggleChanged: value => {
                        SettingsManagerCpp.filterMobileFriendlyApps = value;
                    }
                }

                MSettingsListItem {
                    title: "Search Native Apps"
                    iconName: "search"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.searchNativeApps
                    onToggleChanged: value => {
                        SettingsManagerCpp.searchNativeApps = value;
                    }
                }

                MSettingsListItem {
                    title: "Show Notification Badges"
                    iconName: "bell-ring"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.showNotificationBadges
                    onToggleChanged: value => {
                        SettingsManagerCpp.showNotificationBadges = value;
                    }
                }

                MSettingsListItem {
                    title: "Show Frequent Apps"
                    iconName: "trending-up"
                    showToggle: true
                    toggleValue: SettingsManagerCpp.showFrequentApps
                    onToggleChanged: value => {
                        SettingsManagerCpp.showFrequentApps = value;
                    }
                }
            }

            Item {
                height: 40
            }
        }
    }

    MouseArea {
        property real startY: 0
        property bool isDragging: false

        anchors.fill: parent
        propagateComposedEvents: true
        z: -1
        onPressed: mouse => {
            if (scrollView.contentY <= 0) {
                startY = mouse.y;
                isDragging = false;
            }
        }
        onPositionChanged: mouse => {
            if (scrollView.contentY <= 0) {
                var deltaY = mouse.y - startY;
                if (deltaY > 10)
                    isDragging = true;

                if (isDragging && deltaY > 100) {
                    mainPage.requestClose();
                    isDragging = false;
                }
            }
        }
        onReleased: {
            isDragging = false;
        }
    }

    background: Rectangle {
        color: MColors.background
    }
}
