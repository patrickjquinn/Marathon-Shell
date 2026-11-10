// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clipboard singleton (Silica public API: hasText, text). Clean-room from the
// public documentation. C++ because QML has no clipboard access of its own.
#ifndef KEEL_CLIPBOARD_H
#define KEEL_CLIPBOARD_H

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class KeelClipboard : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Clipboard)
    QML_SINGLETON
    Q_PROPERTY(bool hasText READ hasText NOTIFY textChanged)
    Q_PROPERTY(QString text READ text WRITE setText NOTIFY textChanged)

public:
    explicit KeelClipboard(QObject *parent = nullptr);

    bool hasText() const;
    QString text() const;
    void setText(const QString &text);

signals:
    void textChanged();
};

#endif // KEEL_CLIPBOARD_H
