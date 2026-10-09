// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "logging.h"

namespace keel {

Q_LOGGING_CATEGORY(lcKeelShell, "shipwright.keel.shell", QtInfoMsg)

void enableVerboseLogging()
{
    // QT_LOGGING_RULES, evaluated after these rules, can still override it.
    QLoggingCategory::setFilterRules(QStringLiteral("shipwright.keel.shell.debug=true"));
}

} // namespace keel
