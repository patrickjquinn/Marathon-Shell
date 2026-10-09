// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Media 1.0 MediaPlayerPanelBackground, Keel's stand-in (the public
// documentation lists the type without members): the translucent
// highlight-tinted backdrop of a docked player panel.
import QtQuick 2.6
import Sailfish.Silica 1.0

Rectangle {
    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.rgba(Theme.highlightBackgroundColor, 0.15) }
        GradientStop { position: 1.0; color: Theme.rgba(Theme.highlightBackgroundColor, 0.3) }
    }
}
