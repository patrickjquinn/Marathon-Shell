import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Lists
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Layouts
import QtWebEngine

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

                Column {
                    anchors.fill: parent
                    anchors.margins: MSpacing.lg
                    spacing: MSpacing.md

                    MLabel {
                        width: parent.width
                        text: "Mail wraps your existing webmail. Pick a provider — you can change this any time in Settings → Apps → Mail."
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
                            onClicked: {
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
                        onClicked: customUrlDialog.open()
                    }
                }

                MTextInputModal {
                    id: customUrlDialog

                    title: "Custom webmail URL"
                    placeholder: "https://example.com/mail"
                    initialText: emailApp.customUrl
                    onAccepted: text => {
                        if (text.length === 0)
                            return;

                        emailApp.setCustomUrl(text);
                        emailApp.setProvider("custom");
                        stack.replace(webComponent);
                    }
                }
            }
        }

        Component {
            id: webComponent

            MPage {
                id: webPage

                title: ""
                actionBarVisible: true

                WebEngineView {
                    id: webView

                    anchors.fill: parent
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

                actionBarContent: Row {
                    spacing: MSpacing.sm

                    IconButton {
                        name: "arrow-left"
                        Accessible.name: "Back"
                        enabled: webView.canGoBack
                        onClicked: webView.goBack()
                    }

                    IconButton {
                        name: "rotate-cw"
                        Accessible.name: "Reload"
                        onClicked: webView.reload()
                    }

                    IconButton {
                        name: "settings"
                        Accessible.name: "Switch provider"
                        onClicked: stack.replace(pickerComponent)
                    }
                }
            }
        }
    }
}
