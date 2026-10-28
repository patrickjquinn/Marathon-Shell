// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// Reef's Keel Actions (ADR-0018): search the store, and install, update or
// remove an app. None of the three acts on a caller's word: each brings
// Reef's window to the front with the same confirmation sheet a tap in the
// store shows (everything the transaction will install, update or remove,
// pages/ConfirmPage.qml), and answers only once the person has tapped it
// and the transaction finished, or with Cancelled when they declined.
// keel-mcp also refuses these confirm actions to clients that cannot speak
// for the person.

import QtQuick
import Sailfish.Silica 1.0
import Keel.Actions 1.0
import Shipwright.Reef 1.0

Item {
    id: actions

    // The ApplicationWindow, for app.show's pages.
    property var window

    // The one call waiting for the person and the transaction, the RPM name
    // it is for, and how to answer it once the transaction succeeded.
    property var pendingCall: null
    property string pendingName: ""
    property var pendingReply: null

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

    // The app an entity reference names, or a failed call (null).
    function appFor(args, call) {
        const name = args.app.substring(args.app.lastIndexOf("/") + 1)
        const details = Reef.packageDetails(name)
        if (!details.name) {
            call.fail("Failed", "no app " + name + " in the store")
            return null
        }
        return details
    }

    // Asks Reef for `name` (start(name) shows the sheet); `reply` makes the
    // answer from the package's details once the transaction succeeded.
    function begin(call, name, start, reply) {
        if (Reef.busy || actions.pendingCall || Reef.pendingPlan.length > 0) {
            call.fail("NotAvailable", "Reef is busy with another package")
            return
        }
        actions.pendingCall = call
        actions.pendingName = name
        actions.pendingReply = reply
        start(name)
    }

    function finish() {
        const call = actions.pendingCall
        actions.pendingCall = null
        actions.pendingReply = null
        return call
    }

    Connections {
        target: Reef
        function onOperationFinished(name, ok, message) {
            if (!actions.pendingCall || name !== actions.pendingName)
                return
            const reply = actions.pendingReply
            const call = actions.finish()
            if (ok)
                call.reply(reply(Reef.packageDetails(name)))
            else
                call.fail("Failed", message || "the operation did not finish")
        }
        function onPlanDeclined(name) {
            if (!actions.pendingCall || name !== actions.pendingName)
                return
            actions.finish().fail("Cancelled", "the person declined on Reef's confirmation screen")
        }
    }

    KeelEntity {
        id: appEntity
        type: "app"
        title: "Store app"
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

    KeelAction {
        name: "reef.install"
        title: qsTr("Install an app")
        description: "Install an app from the Reef store on this phone. Reef opens its confirmation screen listing everything the install brings (add-ons, libraries, background services); nothing is installed unless the person taps Install there. Fails with Cancelled when they decline."
        confirm: true
        openWorld: true
        idempotent: true
        // The person reads the screen and decides, then the download.
        timeout: 600000
        parameters: [ KeelParam { name: "app"; type: "entity"; entity: "app"; required: true } ]
        returns: KeelResult {
            type: "object"
            KeelParam { name: "installed"; type: "boolean"; required: true }
            KeelParam { name: "version"; type: "string"; maxLength: 64; required: true }
        }
        onInvoked: (args, call) => {
            const details = actions.appFor(args, call)
            if (!details)
                return
            if (details.installState !== "not_installed") {
                call.reply({ installed: true, version: details.installedVersion || details.version || "" })
                return
            }
            actions.begin(call, details.name, n => Reef.install(n),
                          d => ({ installed: d.installState !== "not_installed",
                                  version: d.installedVersion || d.version || "" }))
        }
    }

    KeelAction {
        name: "reef.update"
        title: qsTr("Update an app")
        description: "Update an installed app from the Reef store. Reef opens its confirmation screen listing everything the update installs or replaces; nothing changes unless the person taps Update there. Fails with Cancelled when they decline."
        confirm: true
        openWorld: true
        idempotent: true
        timeout: 600000
        parameters: [ KeelParam { name: "app"; type: "entity"; entity: "app"; required: true } ]
        returns: KeelResult {
            type: "object"
            KeelParam { name: "updated"; type: "boolean"; required: true }
            KeelParam { name: "version"; type: "string"; maxLength: 64; required: true }
        }
        onInvoked: (args, call) => {
            const details = actions.appFor(args, call)
            if (!details)
                return
            if (details.installState !== "update_available") {
                if (details.installState === "not_installed")
                    call.fail("Failed", details.name + " is not installed")
                else
                    call.reply({ updated: false, version: details.installedVersion || "" })
                return
            }
            actions.begin(call, details.name, n => Reef.update(n),
                          d => ({ updated: d.installState === "installed", version: d.installedVersion || "" }))
        }
    }

    KeelAction {
        name: "reef.remove"
        title: qsTr("Remove an app")
        description: "Remove an app Reef installed. Reef opens its confirmation screen listing everything that would be removed with it, apps that would stop working highlighted; nothing is removed unless the person taps Remove there. Fails with Cancelled when they decline."
        confirm: true
        destructive: true
        idempotent: true
        timeout: 600000
        parameters: [ KeelParam { name: "app"; type: "entity"; entity: "app"; required: true } ]
        returns: KeelResult {
            type: "object"
            KeelParam { name: "removed"; type: "boolean"; required: true }
        }
        onInvoked: (args, call) => {
            const details = actions.appFor(args, call)
            if (!details)
                return
            if (details.installState === "not_installed") {
                call.reply({ removed: true })
                return
            }
            if (details.removable !== true) {
                call.fail("Failed", "Reef did not install " + details.name + ", so it does not remove it")
                return
            }
            actions.begin(call, details.name, n => Reef.remove(n),
                          d => ({ removed: d.installState === "not_installed" || d.installState === undefined }))
        }
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
        description: "Apps installed from Reef, with the updates waiting for them."
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
        description: "Reef's settings: background checks, the repository and licences."
        onShow: actions.showPage("SettingsPage.qml", "")
    }
}
