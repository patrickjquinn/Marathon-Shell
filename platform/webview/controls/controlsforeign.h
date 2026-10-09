// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.WebView.Controls 1.0 on Keel: sailfish-components-webview's
// permission types (MPL-2.0, permission*.{h,cpp}) registered under the names
// upstream's plugin gives them, declaratively, so that the module has
// qmltypes for tooling. The text selection QML (TextSelectionController,
// TextSelectionHandle, TextSelectionToolbar) is in the qmldir.

#ifndef KEEL_WEBVIEW_CONTROLSFOREIGN_H
#define KEEL_WEBVIEW_CONTROLSFOREIGN_H

#include "keelwebenginelink.h"
#include "permissionfilterproxymodel.h"
#include "permissionmanager.h"
#include "permissionmodel.h"

#include <QtQml/qqmlregistration.h>

struct KeelPermissionModelForeign
{
    Q_GADGET
    QML_FOREIGN(PermissionModel)
    QML_NAMED_ELEMENT(PermissionModel)
};

struct KeelPermissionFilterProxyModelForeign
{
    Q_GADGET
    QML_FOREIGN(PermissionFilterProxyModel)
    QML_NAMED_ELEMENT(PermissionFilterProxyModel)
};

struct KeelPermissionManagerForeign
{
    Q_GADGET
    QML_FOREIGN(PermissionManager)
    QML_NAMED_ELEMENT(PermissionManager)
    QML_SINGLETON

public:
    // PermissionManager observes WebEngine's permission topics as it is
    // made, so WebEngine is looked up in this engine first.
    static PermissionManager *create(QQmlEngine *engine, QJSEngine *)
    {
        KeelWebEngineLink::instance(engine);
        return new PermissionManager;
    }
};

#endif // KEEL_WEBVIEW_CONTROLSFOREIGN_H
