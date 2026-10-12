#pragma once

#include <QHash>
#include <QString>
#include <QStringList>

class QQmlContext;

// Marathon.Platform: the service clients the runner gives an app, under the
// names Keel apps use. The older context-property names stay registered.
QHash<QString, QString> platformTypeNames();

// Registers each client already set on the context under its Marathon.Platform
// name; returns the names registered.
QStringList registerPlatformTypes(QQmlContext *context);
