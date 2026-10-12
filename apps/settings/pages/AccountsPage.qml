pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: accountsPage

    property string pageName: "accounts"
    property bool addFormVisible: false
    property string formDisplayName: ""
    property string formBaseUrl: ""
    property string formUsername: ""
    property string formSecret: ""

    pageTitle: "Accounts"
    overlayOpen: removeDialog.showing || addFormVisible
    onCloseOverlayRequested: {
        if (removeDialog.showing) {
            removeDialog.showing = false;
        } else {
            addFormVisible = false;
            resetForm();
        }
    }

    function resetForm() {
        formDisplayName = "";
        formBaseUrl = "";
        formUsername = "";
        formSecret = "";
    }

    content: Flickable {
        contentHeight: accountsContent.height + 40
        clip: true

        Column {
            id: accountsContent

            width: parent.width
            spacing: MSpacing.lg
            leftPadding: MSpacing.lg
            rightPadding: MSpacing.lg
            topPadding: MSpacing.lg

            MSection {
                title: "Sync"
                width: parent.width - MSpacing.lg * 2

                MSettingsListItem {
                    title: DavSyncEngine.syncing ? "Syncing…" : "Idle"
                    value: DavSyncEngine.lastSyncMs > 0 ? Qt.formatDateTime(new Date(DavSyncEngine.lastSyncMs), "MMM d, hh:mm") : "Never"
                }

                MSettingsListItem {
                    title: "Last error"
                    value: DavSyncEngine.lastError
                    visible: DavSyncEngine.lastError && DavSyncEngine.lastError.length > 0
                }
            }

            MSection {
                title: "CardDAV / CalDAV accounts"
                width: parent.width - MSpacing.lg * 2

                Repeater {
                    model: DavSyncEngine.accounts

                    delegate: MSettingsListItem {
                        required property var modelData
                        width: parent.width
                        title: modelData.displayName
                        subtitle: modelData.username + " — " + modelData.baseUrl
                        showChevron: true
                        Accessible.name: "Account " + modelData.displayName + ", tap to remove"
                        onSettingClicked: {
                            removeDialog.targetId = modelData.id;
                            removeDialog.targetName = modelData.displayName;
                            removeDialog.showing = true;
                        }
                    }
                }

                MSettingsListItem {
                    title: "Add account"
                    subtitle: "CardDAV / CalDAV (Nextcloud, Fastmail, iCloud app-password)"
                    showChevron: true
                    onSettingClicked: {
                        accountsPage.resetForm();
                        accountsPage.addFormVisible = true;
                    }
                }
            }

            MSection {
                title: "New account"
                width: parent.width - MSpacing.lg * 2
                visible: accountsPage.addFormVisible

                Column {
                    width: parent.width
                    spacing: MSpacing.sm

                    MTextField {
                        width: parent.width
                        label: "Display name"
                        placeholder: "My Nextcloud"
                        text: accountsPage.formDisplayName
                        onTextChanged: accountsPage.formDisplayName = text
                    }

                    MTextField {
                        width: parent.width
                        label: "Server URL"
                        placeholder: "https://cloud.example.com"
                        text: accountsPage.formBaseUrl
                        onTextChanged: accountsPage.formBaseUrl = text
                    }

                    MTextField {
                        width: parent.width
                        label: "Username"
                        placeholder: "you@example.com"
                        text: accountsPage.formUsername
                        onTextChanged: accountsPage.formUsername = text
                    }

                    MTextField {
                        width: parent.width
                        label: "Password / app-password"
                        placeholder: "••••••••"
                        echoMode: TextInput.Password
                        text: accountsPage.formSecret
                        onTextChanged: accountsPage.formSecret = text
                    }

                    Row {
                        spacing: MSpacing.md

                        MButton {
                            text: "Add"
                            variant: "primary"
                            disabled: accountsPage.formBaseUrl.length === 0 || accountsPage.formUsername.length === 0
                            onClicked: {
                                const display = accountsPage.formDisplayName.length > 0 ? accountsPage.formDisplayName : accountsPage.formUsername;
                                DavSyncEngine.addAccount(display, accountsPage.formBaseUrl, accountsPage.formUsername, accountsPage.formSecret, "basic");
                                accountsPage.addFormVisible = false;
                                accountsPage.resetForm();
                            }
                        }

                        MButton {
                            text: "Cancel"
                            onClicked: {
                                accountsPage.addFormVisible = false;
                                accountsPage.resetForm();
                            }
                        }
                    }
                }
            }

            Row {
                spacing: MSpacing.md
                anchors.horizontalCenter: parent.horizontalCenter

                MButton {
                    text: DavSyncEngine.syncing ? "Syncing…" : "Sync now"
                    variant: "primary"
                    disabled: DavSyncEngine.syncing || DavSyncEngine.accountCount === 0
                    onClicked: DavSyncEngine.syncNow()
                }
            }

            MLabel {
                width: parent.width
                wrapMode: Text.WordWrap
                variant: "secondary"
                text: "CardDAV contacts sync into the device's address book. Calendar collection enumeration is wired; full event ingest follows the same protocol path. Google requires OAuth2; use Nextcloud, Fastmail, iCloud app-passwords, or Mailbox.org for now."
            }
        }
    }

    MConfirmDialog {
        id: removeDialog

        property string targetId: ""
        property string targetName: ""

        title: "Remove account?"
        message: removeDialog.targetName + " will be removed; locally synced contacts are kept."
        confirmText: "Remove account"
        destructive: true
        onConfirmed: {
            DavSyncEngine.removeAccount(removeDialog.targetId);
            removeDialog.showing = false;
        }
        onCancelled: removeDialog.showing = false
    }
}
