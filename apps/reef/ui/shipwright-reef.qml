// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Reef store client, on Keel (Sailfish.Silica 1.0 under Qt6).
// All state comes from the `Reef` singleton (Shipwright.Reef 1.0), a CXX-Qt
// object over reef-backend; its API is documented in ../README.md.

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import Nemo.DBus 2.0
import "pages"
import "actions"

ApplicationWindow {
    id: app

    // Every Label (PageHeader, SectionHeader, ViewPlaceholder, ...) is
    // plain text unless it opts in: catalogue text comes from developers'
    // RPMs, and rich text would load remote images and open any link.
    _defaultLabelFormat: Text.PlainText

    initialPage: Component { CataloguePage { } }
    cover: Qt.resolvedUrl("cover/CoverPage.qml")
    allowedOrientations: defaultAllowedOrientations

    // Keel Actions for Pilot and other MCP clients (actions/ReefActions.qml).
    ReefActions { window: app }

    // The update notification's tap (src/check.rs): Reef on its updates.
    // The session bus starts Reef for it when it is not running
    // (packaging/dbus/org.shipwright.reef.ui.service).
    DBusAdaptor {
        service: "org.shipwright.reef.ui"
        iface: "org.shipwright.reef.ui"
        path: "/"
        xml: '<interface name="org.shipwright.reef.ui"><method name="openUpdates"/></interface>'

        function openUpdates() {
            app.openUpdates()
        }
    }

    function openUpdates() {
        if (!pageStack.currentPage || pageStack.currentPage.objectName !== "installedPage") {
            pageStack.pop(null, PageStackAction.Immediate)
            pageStack.push(Qt.resolvedUrl("pages/InstalledPage.qml"), {}, PageStackAction.Immediate)
        }
        app.activate()
        Reef.refresh()
    }

    // Every install, update and removal waits here for the person: the
    // confirmation sheet lists everything it will do, and only its button
    // starts it. Also for a Keel Action, which brings Reef to the front.
    Connections {
        target: Reef
        function onPlanReady(name, plan) {
            app.pageStack.push(Qt.resolvedUrl("pages/ConfirmPage.qml"), { planJson: plan })
            app.activate()
        }
    }

    Component.onCompleted: {
        if (Reef.refreshOnStart) {
            Reef.refresh()
        }
        // Nothing runs in the background until the person says so.
        // (Once the initial page is on the stack.)
        if (!Reef.backgroundCheckAsked) {
            Qt.callLater(function() {
                pageStack.push(Qt.resolvedUrl("pages/BackgroundChecksPage.qml"))
            })
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
