// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// C++ glue the Qt object model requires (docs/plan.md, "Engineering
// principles"): Rust cannot call `new` on a CXX-Qt QObject, so the Reef
// singleton gets its three list models from here.
#pragma once

#include <QtCore/QObject>

class ReefListModel;

ReefListModel* reef_new_list_model(QObject* parent);
