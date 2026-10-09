// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// keel-shell's logging category, "shipwright.keel.shell". Info and above
// are shown by default; --verbose (or KEEL_SHELL_VERBOSE) enables debug,
// which carries the surface mapping decisions.

#ifndef KEEL_LOGGING_H
#define KEEL_LOGGING_H

#include <QLoggingCategory>

namespace keel {

Q_DECLARE_LOGGING_CATEGORY(lcKeelShell)

// Turns on the category's debug output (--verbose).
void enableVerboseLogging();

} // namespace keel

#endif // KEEL_LOGGING_H
