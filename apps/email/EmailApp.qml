import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Lists
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtWebEngine

// ─────────────────────────────────────────────────────────────────────
//  Mail — current state vs DS target
// ─────────────────────────────────────────────────────────────────────
//
//  This file ships a webmail-provider PICKER that wraps a QtWebEngine
//  view around Gmail / Outlook / Fastmail / etc. It is intentionally
//  NOT the inbox surface shown in the Marathon DS (screens-apps-1.jsx:
//  MailInbox), which is a native list of messages with sender avatars,
//  preview rows, swipe-to-archive, and folder filter chips.
//
//  Bringing the JSX inbox to life requires a real backend:
//    • IMAP (RFC 9051) for fetch / sync, and / or
//    • JMAP (RFC 8620 + 8621) for modern push-based clients,
//    • plus account management UI + secrets storage (SecretService).
//
//  Per direction, that work is queued — we'll ship a real open-standards
//  mail client (IMAP + JMAP) and at that point this picker collapses
//  into either the first-run account setup or is removed entirely.
//
//  Until then the picker keeps DS chrome (tokens, MTopBar, list rows)
//  but the inbox redesign is deferred.
// ─────────────────────────────────────────────────────────────────────

MApp {
    id: emailApp

    readonly property var providers: [
        {
            "id": "gmail",
            "label": "Gmail",
            "url": "https://mail.google.com/mail/mu/"
        },
        {
            "id": "outlook",
            "label": "Outlook",
            "url": "https://outlook.live.com/mail/"
        },
        {
            "id": "fastmail",
            "label": "Fastmail",
            "url": "https://app.fastmail.com/mail/Inbox/"
        },
        {
            "id": "yahoo",
            "label": "Yahoo Mail",
            "url": "https://mail.yahoo.com/"
        },
        {
            "id": "proton",
            "label": "Proton Mail",
            "url": "https://mail.proton.me/"
        },
        {
            "id": "icloud",
            "label": "iCloud Mail",
            "url": "https://www.icloud.com/mail"
        }
    ]
    readonly property string settingsKeyProvider: "email/provider"
    readonly property string settingsKeyCustomUrl: "email/customUrl"
    property string activeProviderId: SettingsManagerCpp.get(settingsKeyProvider, "")
    property string customUrl: SettingsManagerCpp.get(settingsKeyCustomUrl, "")

    function urlForProvider(id) {
        if (id === "custom")
            return customUrl;

        for (var i = 0; i < providers.length; i++) {
            if (providers[i].id === id)
                return providers[i].url;
        }
        return "";
    }

    function setProvider(id) {
        activeProviderId = id;
        SettingsManagerCpp.set(settingsKeyProvider, id);
    }

    function setCustomUrl(url) {
        customUrl = url;
        SettingsManagerCpp.set(settingsKeyCustomUrl, url);
    }

    appId: "email"
    appName: "Mail"
    appIcon: "assets/icon.svg"

    content: Item {
        anchors.fill: parent

        StackView {
            id: stack

            anchors.fill: parent
            initialItem: emailApp.activeProviderId === "" ? pickerComponent : webComponent
        }

        Component {
            id: pickerComponent

            MPage {
                id: pickerPage

                title: "Choose your mail provider"

                content: Column {
                    width: pickerPage.width
                    leftPadding: MSpacing.lg
                    rightPadding: MSpacing.lg
                    topPadding: MSpacing.lg
                    bottomPadding: MSpacing.lg
                    spacing: MSpacing.md

                    MLabel {
                        width: parent.width
                        text: "Mail wraps your existing webmail. Pick a provider; you can change this any time in Settings > Apps → Mail."
                        wrapMode: Text.WordWrap
                        variant: "secondary"
                    }

                    Repeater {
                        model: emailApp.providers

                        delegate: MSettingsListItem {
                            required property var modelData

                            width: pickerPage.width - MSpacing.lg * 2
                            title: modelData.label
                            subtitle: modelData.url
                            Accessible.name: "Use " + modelData.label
                            Accessible.role: Accessible.Button
                            onSettingClicked: {
                                emailApp.setProvider(modelData.id);
                                stack.replace(webComponent);
                            }
                        }
                    }

                    MSettingsListItem {
                        width: pickerPage.width - MSpacing.lg * 2
                        title: "Custom URL"
                        subtitle: emailApp.customUrl || "Enter your own webmail address"
                        Accessible.name: "Use a custom webmail URL"
                        Accessible.role: Accessible.Button
                        onSettingClicked: {
                            customUrlField.text = emailApp.customUrl;
                            customUrlInline.visible = true;
                        }
                    }

                    Row {
                        id: customUrlInline

                        visible: false
                        width: pickerPage.width - MSpacing.lg * 2
                        spacing: MSpacing.sm

                        TextField {
                            id: customUrlField

                            placeholderText: "https://example.com/mail"
                            width: parent.width - applyBtn.width - MSpacing.sm
                        }

                        MButton {
                            id: applyBtn

                            text: "Use"
                            variant: "primary"
                            onClicked: {
                                if (customUrlField.text.length === 0)
                                    return;

                                emailApp.setCustomUrl(customUrlField.text);
                                emailApp.setProvider("custom");
                                stack.replace(webComponent);
                            }
                        }
                    }
                }
            }
        }

        Component {
            id: webComponent

            MPage {
                id: webPage

                title: ""
                showTopBar: false

                content: Item {
                    anchors.fill: parent

                    Rectangle {
                        id: actionBar

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 44
                        color: MColors.elevated

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: MSpacing.md
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: MSpacing.sm

                            MIconButton {
                                iconName: "arrow-left"
                                Accessible.name: "Back"
                                disabled: !webView.canGoBack
                                onClicked: webView.goBack()
                            }

                            MIconButton {
                                iconName: "rotate-cw"
                                Accessible.name: "Reload"
                                onClicked: webView.reload()
                            }

                            MIconButton {
                                iconName: "settings"
                                Accessible.name: "Switch provider"
                                onClicked: stack.replace(pickerComponent)
                            }
                        }
                    }

                    WebEngineView {
                        id: webView

                        anchors.top: actionBar.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        url: emailApp.urlForProvider(emailApp.activeProviderId)
                        settings.javascriptEnabled: true
                        settings.localStorageEnabled: true
                        settings.touchIconsEnabled: true
                        settings.autoLoadIconsForPage: true
                        Accessible.name: "Mail"
                        Accessible.role: Accessible.Document

                        profile: WebEngineProfile {
                            storageName: "marathon-email"
                            offTheRecord: false
                            httpUserAgent: "Mozilla/5.0 (Linux; Marathon Shell) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
                        }
                    }
                }
            }
        }
    }
}
