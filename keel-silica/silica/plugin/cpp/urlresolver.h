// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel-internal helper (not Silica API). Qt 6 no longer resolves a relative
// URL when it is assigned to a url property; an Image resolves it against
// its own QML context when it loads. An Image inside a Keel control that an
// app reaches through an alias (`icon.source: "/usr/share/..."` on
// CoverPlaceholder, Button, IconButton, Switch, IconTextSwitch) would resolve
// the app's string against Keel's compiled-in qrc:/Sailfish/Silica/... URL.
// fixSource() re-resolves it against the context the control was declared
// in (the app's file), as the app author meant. It writes through
// QObject::setProperty, which keeps the app's binding in place.
#ifndef KEEL_URLRESOLVER_H
#define KEEL_URLRESOLVER_H

#include <QObject>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class KeelUrlResolver : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(KeelUrlResolver)
    QML_SINGLETON

public:
    using QObject::QObject;

    // `url` resolved against the QML context `contextObject` was created in.
    Q_INVOKABLE QUrl resolve(const QUrl &url, QObject *contextObject) const;
    // Rewrites `target`'s `property` (default "source") to the resolved URL
    // when it is relative or a bare absolute path.
    Q_INVOKABLE void fixSource(QObject *target, QObject *contextObject,
                               const QString &property = QStringLiteral("source")) const;
    // fixSource() against the nearest ancestor of `target` that was declared
    // outside Keel's Silica QML (the app's control, for an image inside one
    // of Silica's BSD controls such as Button's or IconButton's Icon).
    Q_INVOKABLE void fixSourceForControl(QObject *target,
                                         const QString &property = QStringLiteral("source")) const;
};

#endif
