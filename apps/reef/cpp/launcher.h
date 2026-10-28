// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// The app window through Keel's SailfishApp library; see launcher.cpp.
#pragma once

#include <QtCore/QString>
#include <QtCore/QStringList>

class QGuiApplication;

// Loads `qmlPath` (a local QML file whose root is Keel's ApplicationWindow)
// into SailfishApp::createView() and shows it. A root that is not an Item
// (a smoke-test harness) is created in the view's engine and not shown.
// False, with the errors printed, if it does not load. The QGuiApplication
// must exist.
bool keel_show_main_view(const QString& qmlPath);

// Deletes the main view (its engine and the QML objects in it) after the
// event loop has ended, so that their threads stop before the process exits.
void keel_destroy_main_view();

// Keel::application(): the QGuiApplication, booster-keel's when boosted
// (ADR-0016), otherwise created from the command line. The Rust main uses
// it instead of creating its own.
QGuiApplication* keel_application();

// Keel::launchArguments(): the app's command line, also when boosted (where
// Rust's std::env::args() is the booster's).
QStringList keel_launch_arguments();
