// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Reef store client, on Keel (Sailfish.Silica 1.0 under Qt6).
// All state comes from the `Reef` singleton (Shipwright.Reef 1.0), a CXX-Qt
// object over reef-backend; its API is documented in ../UI.md.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "pages"
import "actions"

ApplicationWindow {
    id: app

    // Every Label (PageHeader, SectionHeader, ViewPlaceholder, ...) is
    // plain text unless it opts in: catalogue text comes from developers,
    // and rich text would load remote images and open any link.
    _defaultLabelFormat: Text.PlainText

    initialPage: Component { CataloguePage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    // Keel Actions for Pilot and other MCP clients (actions/ReefActions.qml).
    ReefActions { window: app }

    Component.onCompleted: {
        if (Reef.refreshOnStart) {
            Reef.refresh()
        }
    }

    // Back from the browser after Buy: fetch the licence if it is paid
    // (only while a purchase's claim code is pending; at most every 10 s).
    onApplicationActiveChanged: {
        if (applicationActive) {
            Reef.checkPurchases()
        }
    }
}
