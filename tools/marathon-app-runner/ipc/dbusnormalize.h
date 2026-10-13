#pragma once

#include <QVariant>

// D-Bus replies hand nested containers back as QDBusArgument or QDBusVariant;
// these turn them into plain QVariantMap/QVariantList all the way down.
QVariant     normalizeDbusVariantDeep(QVariant v);
QVariantMap  normalizeMapDeep(const QVariantMap &in);
QVariantList normalizeListDeep(const QVariantList &in);
QVariantList unwrapDbusVariantList(const QVariant &v);
