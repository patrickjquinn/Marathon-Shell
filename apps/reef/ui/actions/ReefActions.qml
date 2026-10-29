// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Reef's Keel Actions (ADR-0018): search the store, open an app's page,
// install an app and update every app (both after the person's yes), and
// show the store's pages.

import QtQuick
import Sailfish.Silica 1.0
import Keel.Actions 1.0
import Shipwright.Reef 1.0

Item {
    id: actions

    // The ApplicationWindow, for app.show's pages.
    property var window

    function summary(row) {
        return {
            id: row.name,
            title: row.title || row.name,
            summary: row.summary || "",
            category: row.category || "",
            version: row.version || "",
            installed: row.installState === "installed" || row.installState === "update_available"
        };
    }

    // Every app the query finds, ranked as the search page ranks them.
    function matches(query, limit) {
        return Reef.findApps(query, limit).map(actions.summary);
    }

    // The app with this id, or null.
    function app(id) {
        const row = Reef.appRow(String(id || ""));
        return row.name ? row : null;
    }

    KeelEntity {
        id: appEntity
        type: "app"
        title: qsTr("Store app")
        description: "An app in the Reef store: its name, summary, category, version and whether it is installed."
        KeelParam {
            name: "summary"
            type: "string"
            maxLength: 200
            summarisable: true
            indexable: true
        }
        KeelParam {
            name: "category"
            type: "string"
            maxLength: 64
            summarisable: true
            indexable: true
        }
        KeelParam {
            name: "version"
            type: "string"
            maxLength: 64
            summarisable: true
        }
        KeelParam {
            name: "installed"
            type: "boolean"
            summarisable: true
        }
        onResolve: (id, call) => {
            const row = actions.app(id);
            call.reply(row ? actions.summary(row) : null);
        }
        onFind: (query, limit, call) => call.reply(actions.matches(query, limit))
    }

    KeelAction {
        name: "reef.search"
        title: qsTr("Search the store")
        description: "Search the Reef store's catalogue by name, summary or category. Returns matching apps and whether each is installed."
        readOnly: true
        idempotent: true
        parameters: [
            KeelParam {
                name: "query"
                type: "string"
                required: true
                maxLength: 256
            }
        ]
        returns: KeelResult {
            type: "array"
            itemType: "object"
            maxItems: 50
            KeelParam {
                name: "app"
                type: "entity"
                entity: "app"
                required: true
            }
            KeelParam {
                name: "id"
                type: "string"
                maxLength: 256
                required: true
            }
            KeelParam {
                name: "title"
                type: "string"
                maxLength: 256
                required: true
            }
            KeelParam {
                name: "summary"
                type: "string"
                maxLength: 200
                required: true
            }
            KeelParam {
                name: "installed"
                type: "boolean"
                required: true
            }
        }
        onInvoked: (args, call) => call.reply(actions.matches(args.query, 50).map(s => {
                return {
                    app: appEntity.uri(s.id),
                    id: s.id,
                    title: s.title,
                    summary: s.summary,
                    installed: s.installed
                };
            }))
    }

    KeelAction {
        name: "reef.open"
        title: qsTr("Show an app in the store")
        description: "Show an app's page in the Reef store: what it is, what it may use, and Install or Open."
        idempotent: true
        parameters: [
            KeelParam {
                name: "app"
                type: "string"
                required: true
                maxLength: 256
                description: "The app's id, from reef.search"
            }
        ]
        onInvoked: (args, call) => {
            if (!actions.app(args.app)) {
                call.fail("NotFound", "No such app in the store");
                return;
            }
            actions.showPage("PackagePage.qml", "", {
                packageName: args.app
            });
            actions.window.activate();
            call.reply();
        }
    }

    KeelAction {
        name: "reef.install"
        title: qsTr("Install an app")
        description: "Install an app from the Reef store (Flathub, F-Droid or Reef's own). Runs in the background; reef.search says when it is installed."
        confirm: true
        openWorld: true
        parameters: [
            KeelParam {
                name: "app"
                type: "string"
                required: true
                maxLength: 256
                description: "The app's id, from reef.search"
            }
        ]
        onInvoked: (args, call) => {
            const row = actions.app(args.app);
            if (!row)
                call.fail("NotFound", "No such app in the store");
            else if (!row.installable)
                call.fail("NotAvailable", "This app can't be installed on Marathon");
            else if (row.blocked)
                call.fail("NotAvailable", "This phone can't run this app");
            else if (row.installState !== "not_installed")
                call.fail("NotAvailable", "Already installed");
            else {
                Reef.install(args.app);
                call.reply();
            }
        }
    }

    KeelAction {
        name: "reef.update_all"
        title: qsTr("Update all apps")
        description: "Install every update waiting for apps from the store."
        confirm: true
        openWorld: true
        onInvoked: (args, call) => {
            Reef.updateAll();
            call.reply();
        }
    }

    // app.show's pages, each from the store's first page (asking twice does
    // not stack it twice), as its pull-down menu opens them.
    function showPage(file, objectName, properties) {
        const stack = actions.window.pageStack;
        if (stack.currentPage && stack.currentPage.objectName === objectName && objectName !== "")
            return;
        if (stack.depth > 1)
            stack.pop(null, PageStackAction.Immediate);
        stack.push(Qt.resolvedUrl("../pages/" + file), properties || {});
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
