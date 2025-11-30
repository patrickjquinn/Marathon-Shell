import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MarathonUI.Core
import MarathonUI.Containers
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: page
    anchors.fill: parent
    color: MColors.background

    MScrollView {
        anchors.fill: parent

        ColumnLayout {
            width: page.width
            spacing: 0

            // Hero Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 280
                color: MColors.marathonTeal

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: MSpacing.lg
                    width: parent.width - (MSpacing.xl * 2)

                    MLabel {
                        text: "App Store"
                        font.pixelSize: 36
                        font.weight: Font.Bold
                        color: MColors.background
                        Layout.alignment: Qt.AlignHCenter
                    }

                    MLabel {
                        text: "Discover and install apps built for Marathon"
                        font.pixelSize: 16
                        color: MColors.background
                        opacity: 0.9
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        Layout.alignment: Qt.AlignHCenter
                        Layout.fillWidth: true
                    }

                    MButton {
                        text: "Coming Soon"
                        variant: "secondary"
                        enabled: false
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: MSpacing.sm
                    }
                }
            }

            // Features Grid
            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: MSpacing.xl
                spacing: MSpacing.lg

                MLabel {
                    text: "What's Coming"
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 1
                    rowSpacing: MSpacing.md
                    columnSpacing: MSpacing.md

                    Repeater {
                        model: [
                            {
                                title: "Curated Catalog",
                                desc: "Browse hand-picked Marathon apps",
                                icon: "📱"
                            },
                            {
                                title: "Secure Installation",
                                desc: "GPG-verified packages with signature checking",
                                icon: "🔒"
                            },
                            {
                                title: "Smart Permissions",
                                desc: "Runtime permission prompts for user privacy",
                                icon: "🛡"
                            },
                            {
                                title: "Automatic Updates",
                                desc: "Keep your apps up-to-date automatically",
                                icon: "🔄"
                            },
                            {
                                title: "Developer Tools",
                                desc: "CLI tools for packaging and signing apps",
                                icon: ""
                            },
                            {
                                title: "Fast & Native",
                                desc: "QML apps optimized for ARM performance",
                                icon: ""
                            }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 90
                            color: MColors.surface
                            radius: MRadius.md
                            border.width: 1
                            border.color: MColors.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: MSpacing.lg
                                spacing: MSpacing.lg

                                MLabel {
                                    text: modelData.icon
                                    font.pixelSize: 32
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: MSpacing.xs

                                    MLabel {
                                        text: modelData.title
                                        font.pixelSize: 16
                                        font.weight: Font.Bold
                                    }

                                    MLabel {
                                        text: modelData.desc
                                        variant: "secondary"
                                        font.pixelSize: 13
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                }

                // Developer Info
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120
                    Layout.topMargin: MSpacing.lg
                    color: MColors.bb10Elevated
                    radius: MRadius.md
                    border.width: 1
                    border.color: MColors.borderGlass

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: MSpacing.md
                        width: parent.width - (MSpacing.xl * 2)

                        MLabel {
                            text: "For Developers"
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignHCenter
                        }

                        MLabel {
                            text: "Package and publish your Marathon apps using the marathon-dev CLI tool"
                            variant: "secondary"
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: MSpacing.xl
            }
        }
    }
}
