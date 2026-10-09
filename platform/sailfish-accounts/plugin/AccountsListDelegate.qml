// SPDX-FileCopyrightText: 2015 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2024 - 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Accounts 1.0

ListItem {
    id: delegateItem

    property bool entriesInteractive
    property bool allowRemoveOnly

    readonly property bool notSignedIn: model.accountError === AccountModel.AccountNotSignedInError
    readonly property bool valid: notSignedIn || model.accountError === AccountModel.NoAccountError

    signal accountRemoveRequested(int accountId)
    signal accountSyncRequested(int accountId)
    signal accountClicked(int accountId, string providerName)

    contentHeight: visible
                   ? Math.max(icon.height,
                              column.height + (errorLabel.visible ? errorLabel.height : 0))
                     + 2*Theme.paddingSmall
                   : 0
    menu: entriesInteractive ? menuComponent : null

    Component {
        id: menuComponent

        ContextMenu {
            MenuLabel {
                text: {
                    if (model.accountReadOnly && model.accountLimited) {
                        //: Displayed if the account is read-only and limited
                        //% "Account is read-only and limited"
                        return qsTrId("components_accounts-la-account_read_only_limited")
                    }
                    if (model.accountReadOnly) {
                        //: Displayed if the account is read-only
                        //% "Account is read-only"
                        return qsTrId("components_accounts-la-account_read_only")
                    }
                    //: Displayed if the account is limited
                    //% "Account is limited"
                    return qsTrId("components_accounts-la-account_limited")
                }
                visible: model.accountReadOnly || model.accountLimited
            }
            MenuItem {
                visible: model.providerName !== "jolla"
                         && !model.accountReadOnly
                         && !model.accountLimited
                         && !delegateItem.allowRemoveOnly
                text: model.accountEnabled
                      ? //: Disables a user account
                        //% "Disable"
                        qsTrId("components_accounts-me-disable")
                      : //: Enables a user account
                        //% "Enable"
                        qsTrId("components_accounts-me-enable")
                onClicked: {
                    accountModel.setAccountEnabled(model.accountId, !accountEnabled)
                }
            }

            MenuItem {
                visible: !model.accountReadOnly && !model.accountLimited
                //: Deletes a user account
                //% "Delete"
                text: qsTrId("components_accounts-me-delete_account")
                onClicked: removeAccount()
            }

            MenuItem {
                //: Syncs the data for this account
                //% "Sync"
                text: qsTrId("components_accounts-me-sync")
                visible: !notSignedIn && model.accountEnabled
                         && (model.providerName === "activesync"
                             || accountSyncManager.profileIds(model.accountId).length > 0)
                         && !delegateItem.allowRemoveOnly

                onClicked: {
                    delegateItem.accountSyncRequested(model.accountId)
                }
            }
        }
    }

    function removeAccount() {
        remorseDelete(function() { delegateItem.accountRemoveRequested(model.accountId) })
    }

    ListView.onRemove: animateRemoval()

    Binding {
        target: icon
        property: "opacity"
        when: !delegateItem.highlighted // don't change the opacity while the context menu is open
        value: model.accountEnabled && !syncIndicator.running ? 1.0 : 0.3
    }

    AccountIcon {
        id: icon

        x: Theme.horizontalPageMargin
        y: Math.max(Theme.paddingSmall, -height / 2 + column.y + column.height / 2)
        source: model.accountIcon
    }
    BusyIndicator {
        id: syncIndicator

        anchors.centerIn: icon
        size: BusyIndicatorSize.Small
        height: width
        running: model.performingInitialSync && model.accountError === AccountModel.NoAccountError
    }
    Column {
        id: column

        anchors {
            left: icon.right
            leftMargin: Theme.paddingLarge
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
            verticalCenterOffset: errorLabel.visible ? -(errorLabel.height / 2) : 0
        }
        Label {
            width: parent.width
            truncationMode: TruncationMode.Fade
            text: model.accountDisplayName
            color: {
                if (highlighted || !valid) {
                    return Theme.highlightColor
                }
                return model.accountEnabled
                        ? Theme.primaryColor
                        : Theme.rgba(Theme.primaryColor, 0.55)
            }
        }
        Label {
            width: parent.width
            visible: text.length > 0
            truncationMode: TruncationMode.Fade
            text: {
                if (model.performingInitialSync) {
                    //: In the process of setting up this account
                    //% "Setting up account..."
                    return qsTrId("component_accounts-la-setting_up_account")
                }
                return model.accountUserName
            }
            color: {
                if (highlighted || !valid) {
                    return Theme.secondaryHighlightColor
                }
                return model.accountEnabled
                        ? Theme.secondaryColor
                        : Theme.rgba(Theme.secondaryColor, 0.3)
            }
        }
    }

    Label {
        id: errorLabel

        anchors {
            left: icon.right
            leftMargin: Theme.paddingLarge
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            top: column.bottom
        }

        width: parent.width
        visible: notSignedIn
        truncationMode: TruncationMode.Fade
        color: Theme.errorColor
        //: The user has not logged into this account
        //% "Account not signed in"
        text: qsTrId("component_accounts-la-not_signed_in2")
        font.pixelSize: Theme.fontSizeSmall
    }

    onClicked: {
        if (allowRemoveOnly) {
            openMenu()
        } else {
            delegateItem.accountClicked(model.accountId, model.providerName)
        }
    }
}
