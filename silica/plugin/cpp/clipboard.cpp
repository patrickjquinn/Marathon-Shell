// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "clipboard.h"

#include <QClipboard>
#include <QGuiApplication>

KeelClipboard::KeelClipboard(QObject *parent)
    : QObject(parent)
{
    if (QClipboard *cb = QGuiApplication::clipboard())
        connect(cb, &QClipboard::dataChanged, this, &KeelClipboard::textChanged);
}

bool KeelClipboard::hasText() const
{
    return !text().isEmpty();
}

QString KeelClipboard::text() const
{
    QClipboard *cb = QGuiApplication::clipboard();
    return cb ? cb->text() : QString();
}

void KeelClipboard::setText(const QString &text)
{
    QClipboard *cb = QGuiApplication::clipboard();
    if (!cb || cb->text() == text)
        return;
    cb->setText(text);
    // Some platforms (offscreen, minimal) do not emit dataChanged.
    emit textChanged();
}
