// SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Accounts 1.0

SilicaListView {
    id: root

    //-------------- api

    property alias filterType: accountModel.filterType
    property alias filter: accountModel.filter
    property bool entriesInteractive

    signal accountClicked(int accountId, string providerName)
    signal accountRemoveRequested(int accountId)
    signal accountSyncRequested(int accountId)

    //-------------- impl

    property bool _hideJollaAccount

    model: AccountModel { id: accountModel }

    delegate: AccountsListDelegate {
        id: delegateItem

        enabled: root.entriesInteractive
        visible: !root._hideJollaAccount || model.providerName !== "jolla"
        entriesInteractive: root.entriesInteractive

        onAccountSyncRequested: root.accountSyncRequested(accountId)
        onAccountRemoveRequested: root.accountRemoveRequested(accountId)
        onAccountClicked: root.accountClicked(accountId, providerName)
    }

    AccountSyncManager {
        id: accountSyncManager
    }

    AccountManager { id: accountManager }
    VerticalScrollDecorator {}
}
