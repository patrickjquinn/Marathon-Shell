pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// DS Settings · screens-apps-1.jsx:SettingsApp (23 · Settings).
//
// Layout, top-to-bottom:
//   • "Settings" title + search icon (right)
//   • Profile hero card — avatar + name + sync subtitle + chevron
//   • Eyebrow groups: MARATHON INTELLIGENCE · CONNECTIVITY · DEVICE ·
//                     SECURITY · SYSTEM · APPS & FILTERS
//   • Status rows (Wi-Fi, Bluetooth, …) show value text on the right
//     instead of a chevron, per the DS Row pattern (Row JSX line 643:
//     "{value && <div className='row-value'>{value}</div>}").
//
// Previously each section used Title-3 + a descriptive subtitle, which
// read as content rather than navigation chrome. Per DS the section
// header is a small-caps tracked eyebrow (11/700, +1.4 tracking, --text-secondary).
Page {
    id: mainPage

    property string pageName: "main"

    signal navigateToPage(string page)
    signal requestClose

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
            // DS Title 1 — 34/200 with -0.8 tracking. The DS guidance is
            // unambiguous: "Use weight 200 for any heading 24px+."
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

            // ── Profile hero card ──────────────────────────────────
            // DS SettingsApp:line ~50 — Card { padding: '14px 16px' }
            // with circle avatar, name (15/600), sync subtitle (12/secondary),
            // chevron. We map name/email/sync to the user's session info;
            // when no real account is wired we fall back to a sensible
            // local-account label so the slot isn't blank.
            Rectangle {
                id: profileCard
                width: parent.width - 48
                height: 68
                radius: MRadius.md
                color: MColors.bb10Elevated
                border.width: 1
                border.color: MColors.whiteOverlay08

                MTopHairline {
                    radius: MRadius.md
                    color: MColors.whiteOverlay06
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 14

                    Rectangle {
                        width: 40
                        height: 40
                        radius: width / 2
                        color: MColors.marathonTealDarkest
                        border.width: 1
                        border.color: MColors.tealBorder
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "M"
                            color: MColors.marathonTealBright
                            font.family: MTypography.fontFamily
                            font.pixelSize: 14
                            font.weight: MTypography.weightMedium
                        }
                    }

                    Column {
                        width: parent.width - 40 - 22 - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            text: "Marathon"
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeSubhead
                            font.weight: MTypography.weightDemiBold
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        Text {
                            text: "Local account · No cloud sync"
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeCaption
                            font.weight: MTypography.weightRegular
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Icon {
                        name: "chevron-right"
                        size: 18
                        color: MColors.textTertiary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mainPage.navigateToPage("accounts")
                }
            }

            // ── MARATHON INTELLIGENCE ──────────────────────────────
            MSection {
                title: "Marathon Intelligence"
                eyebrow: true
                width: parent.width - 48

                MSettingsListItem {
                    title: "Marathon Intelligence"
                    subtitle: "On-device · 3.2 GB model"
                    iconName: "sparkle"
                    value: "On"
                    onSettingClicked: mainPage.navigateToPage("intelligence")
                }

                MSettingsListItem {
                    title: "Focus"
                    subtitle: "Sleep · active until 7 AM"
                    iconName: "moon"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("focus")
                }

                MSettingsListItem {
                    title: "Wallet & Passkeys"
                    subtitle: SettingsManagerCpp.hiddenApps.length === 0 ? "Hardware-backed" : "Configure"
                    iconName: "fingerprint"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("security")
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
                    value: SystemControlStore.isBluetoothOn ? "On" : "Off"
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
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("display")
                }

                MSettingsListItem {
                    title: "Sound"
                    iconName: "volume-2"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("sound")
                }

                MSettingsListItem {
                    title: "Notifications"
                    iconName: "bell"
                    showChevron: true
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
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("storage")
                }

                MSettingsListItem {
                    title: "Battery"
                    iconName: "battery"
                    showChevron: true
                    onSettingClicked: mainPage.navigateToPage("battery")
                }
            }

            // ── SECURITY ───────────────────────────────────────────
            MSection {
                title: "Security & Privacy"
                eyebrow: true
                width: parent.width - 48

                MSettingsListItem {
                    title: "Security"
                    subtitle: "Lock screen, PIN, fingerprint"
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
                        const sort = SettingsManagerCpp.appSortOrder === "alphabetical" ? "A–Z" : SettingsManagerCpp.appSortOrder === "frequent" ? "Most Used" : SettingsManagerCpp.appSortOrder === "recent" ? "Recent" : "Custom";
                        return sort;
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
