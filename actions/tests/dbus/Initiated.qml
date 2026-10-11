// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// A test app whose one action answers with what the runtime told it about
// the call: whether the person started it. Served by keel-actions-test-host
// for tst_dbus's caller-trust check (keel/actions/plugin/keelcallertrust.h).
import QtQuick 2.15
import Keel.Actions 1.0

Item {
    KeelAction {
        name: "probe.initiated"
        description: "Test action that answers whether the call reached the app as started by the person."
        readOnly: true
        returns: KeelResult { type: "boolean" }
        onInvoked: (args, call) => call.reply(call.userInitiated)
    }
}
