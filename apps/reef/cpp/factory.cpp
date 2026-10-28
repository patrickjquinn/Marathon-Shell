// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

#include "shipwright-reef/cpp/factory.h"
#include "shipwright-reef/src/bridge.cxxqt.h"

ReefListModel* reef_new_list_model(QObject* parent)
{
    // Owned by `parent` (the Reef singleton) through the QObject tree, so QML
    // never takes ownership of it.
    return new ReefListModel(parent);
}
