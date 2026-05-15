import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// Marathon DS · Store · Discover (screens-apps-2.jsx:StoreDiscover).
//
// MTopBar "Store" + 32 px avatar. Hero card with EDITORS' PICK chip,
// featured title + author + Get + Preview. "Trending now" 3-up tile
// row (icon + name + rating). "Updates available · N" rows with
// Update buttons. Bottom tabs handled by parent (Discover / Apps /
// Installed / Account).
Rectangle {
    id: page

    anchors.fill: parent
    color: MColors.background

    Column {
        anchors.fill: parent
        spacing: 0

        // ── Header ─────────────────────────────────────────
        MTopBar {
            id: topBar
            width: parent.width
            title: "Store"
            actions: [
                Rectangle {
                    width: 32
                    height: 32
                    radius: width / 2
                    color: MColors.elev3
                    border.width: 1
                    border.color: MColors.whiteOverlay08
                    Icon {
                        anchors.centerIn: parent
                        name: "user"
                        size: 16
                        color: MColors.textSecondary
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: HapticService.light()
                    }
                }
            ]
        }

        // ── Scrollable content ─────────────────────────────
        Flickable {
            width: parent.width
            height: parent.height - topBar.height
            clip: true
            contentHeight: contentCol.height
            contentWidth: width

            Column {
                id: contentCol
                width: parent.width
                spacing: 18
                topPadding: 16
                bottomPadding: 20

                // ── Editors' Pick hero ──
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    height: 160
                    radius: MRadius.md
                    color: MColors.elev2
                    border.width: 1
                    border.color: MColors.tealBorder

                    // Soft teal glow in top-right corner.
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: -20
                        anchors.rightMargin: -20
                        width: 140
                        height: 140
                        radius: width / 2
                        color: MColors.marathonTealBright
                        opacity: 0.10
                    }

                    Column {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 14
                        anchors.bottomMargin: 14
                        spacing: 8

                        // EDITORS' PICK eyebrow chip.
                        Rectangle {
                            width: pickText.implicitWidth + 16
                            height: 22
                            radius: 2
                            color: MColors.marathonTealBright
                            Text {
                                id: pickText
                                anchors.centerIn: parent
                                text: "EDITORS' PICK"
                                color: "#000000"
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeEyebrow
                                font.weight: Font.Bold
                                font.letterSpacing: MTypography.trackingEyebrow
                            }
                        }

                        Text {
                            text: "Slate Editor — for writing that doesn't fight back"
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            font.letterSpacing: -0.2
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }

                        Text {
                            text: "Curlybrace Labs · Free with in-app pro tier"
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                        }

                        Row {
                            spacing: 8
                            MButton {
                                text: "Get"
                                variant: "primary"
                                size: "compact"
                            }
                            MButton {
                                text: "Preview"
                                variant: "secondary"
                                size: "compact"
                            }
                        }
                    }
                }

                // ── Trending now ────
                Column {
                    width: parent.width
                    spacing: 10

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Trending now"
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        font.letterSpacing: -0.2
                    }
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Top picks from across the system"
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 8
                        spacing: 10

                        Repeater {
                            model: [
                                {
                                    name: "Lattice",
                                    sub: "Tasks · 4.8",
                                    glyph: "check",
                                    primary: true
                                },
                                {
                                    name: "Sigil",
                                    sub: "Password · 4.5",
                                    glyph: "shield"
                                },
                                {
                                    name: "Tide",
                                    sub: "Sleep · 4.7",
                                    glyph: "moon"
                                }
                            ]
                            delegate: Column {
                                width: (parent.width - parent.spacing * 2) / 3
                                spacing: 6

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: width
                                    radius: MRadius.squircle
                                    color: modelData.primary ? MColors.marathonTealBright : MColors.elev3
                                    border.width: 1
                                    border.color: modelData.primary ? MColors.tealBorder : MColors.whiteOverlay08
                                    Icon {
                                        anchors.centerIn: parent
                                        name: modelData.glyph
                                        size: 32
                                        color: modelData.primary ? "#000000" : MColors.textPrimary
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.name
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    font.weight: Font.Medium
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.sub
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeEyebrow
                                }
                            }
                        }
                    }
                }

                // ── Updates available ────
                Column {
                    width: parent.width
                    spacing: 10

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Updates available · 2"
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.Medium
                        font.letterSpacing: -0.2
                    }

                    Repeater {
                        model: [
                            {
                                name: "Browser",
                                desc: "Faster tab switcher, fixes 12 bugs"
                            },
                            {
                                name: "Slate Notes",
                                desc: "New outliner, sync redesign"
                            }
                        ]
                        delegate: Item {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            height: 60

                            Row {
                                anchors.fill: parent
                                spacing: 12

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 40
                                    height: 40
                                    radius: MRadius.squircle
                                    color: MColors.elev3
                                    border.width: 1
                                    border.color: MColors.whiteOverlay08
                                    Icon {
                                        anchors.centerIn: parent
                                        name: index === 0 ? "globe" : "file-text"
                                        size: 18
                                        color: MColors.textSecondary
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 40 - 80 - parent.spacing * 2
                                    spacing: 2
                                    Text {
                                        text: modelData.name
                                        color: MColors.textPrimary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeSubhead
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        width: parent.width
                                        text: modelData.desc
                                        color: MColors.textSecondary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeFootnote
                                        elide: Text.ElideRight
                                    }
                                }

                                MButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Update"
                                    variant: "primary"
                                    size: "compact"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
