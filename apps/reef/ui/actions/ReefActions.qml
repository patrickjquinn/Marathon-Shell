// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Reef's Keel Actions (ADR-0018): search the store and show its pages.
// Installing, updating and removing apps come with Marathon's installs.

import QtQuick
import Sailfish.Silica 1.0
import Keel.Actions 1.0
import Shipwright.Reef 1.0

Item {
    id: actions

    // The ApplicationWindow, for app.show's pages.
    property var window

    function rows() {
        // get() answers {} past the last row.
        const model = Reef.catalogueModel
        const out = []
        for (let i = 0; i < 10000; ++i) {
            const row = model.get(i)
            if (!row.name)
                break
            out.push(row)
        }
        return out
    }

    function summary(row) {
        return { id: row.name, title: row.title || row.name, summary: row.summary || "",
                 category: row.category || "", version: row.version || "",
                 installed: row.installState === "installed" || row.installState === "update_available" }
    }

    function matches(query) {
        const q = query.toLowerCase()
        return rows().filter(r => (r.name + " " + (r.title || "") + " " + (r.summary || "") + " " + (r.category || ""))
                             .toLowerCase().indexOf(q) >= 0)
    }

    KeelEntity {
        id: appEntity
        type: "app"
        title: qsTr("Store app")
        description: "An app in the Reef store: its name, summary, category, version and whether it is installed."
        KeelParam { name: "summary"; type: "string"; maxLength: 200; summarisable: true; indexable: true }
        KeelParam { name: "category"; type: "string"; maxLength: 64; summarisable: true; indexable: true }
        KeelParam { name: "version"; type: "string"; maxLength: 64; summarisable: true }
        KeelParam { name: "installed"; type: "boolean"; summarisable: true }
        onResolve: (id, call) => {
            const row = actions.rows().find(r => r.name === id)
            call.reply(row ? actions.summary(row) : null)
        }
        onFind: (query, limit, call) => call.reply(actions.matches(query).slice(0, limit).map(actions.summary))
    }

    KeelAction {
        name: "reef.search"
        title: qsTr("Search the store")
        description: "Search the Reef store's catalogue by name, summary or category. Returns matching apps and whether each is installed."
        readOnly: true
        idempotent: true
        parameters: [ KeelParam { name: "query"; type: "string"; required: true; maxLength: 256 } ]
        returns: KeelResult {
            type: "array"; itemType: "object"; maxItems: 50
            KeelParam { name: "app"; type: "entity"; entity: "app"; required: true }
            KeelParam { name: "title"; type: "string"; maxLength: 256; required: true }
            KeelParam { name: "summary"; type: "string"; maxLength: 200; required: true }
            KeelParam { name: "installed"; type: "boolean"; required: true }
        }
        onInvoked: (args, call) => call.reply(actions.matches(args.query).slice(0, 50).map(r => {
            const s = actions.summary(r)
            return { app: appEntity.uri(s.id), title: s.title, summary: s.summary, installed: s.installed }
        }))
    }

    // app.show's pages, each from the store's first page (asking twice does
    // not stack it twice), as its pull-down menu opens them.
    function showPage(file, objectName) {
        const stack = actions.window.pageStack
        if (stack.currentPage && stack.currentPage.objectName === objectName && objectName !== "")
            return
        if (stack.depth > 1)
            stack.pop(null, PageStackAction.Immediate)
        stack.push(Qt.resolvedUrl("../pages/" + file))
    }

    KeelPage {
        name: "installed"
        title: qsTr("Installed")
        description: "Apps installed from Reef."
        onShow: actions.showPage("InstalledPage.qml", "installedPage")
    }

    KeelPage {
        name: "licences"
        title: qsTr("Licences")
        description: "The paid apps' licences on this phone."
        onShow: actions.showPage("LicencesPage.qml", "")
    }

    KeelPage {
        name: "settings"
        title: qsTr("Settings")
        description: "Reef's settings: where the store is, and licences."
        onShow: actions.showPage("SettingsPage.qml", "")
    }
}
