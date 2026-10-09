// SPDX-FileCopyrightText: 2013 - 2023 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause

#include "globalaccountmanager_p.h"
#include <QThreadStorage>

QThreadStorage<Accounts::Manager *> g_accountManagers;

Accounts::Manager *globalAccountManager()
{
    if (!g_accountManagers.hasLocalData()) {
        g_accountManagers.setLocalData(new Accounts::Manager);
    }

    return g_accountManagers.localData();
}
