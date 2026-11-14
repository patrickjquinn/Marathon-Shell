// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// EnterKey attached type (Silica public API: enabled, highlighted, iconSource,
// text, clicked()). Clean-room from the public documentation. Attached types
// need a C++ QObject with qmlAttachedProperties, so this is thin C++.
//
// A Return/Enter key press while the attachee (or an item inside it, such as
// a TextField's editor) has the active focus emits clicked() when enabled,
// and is consumed, except by a multi-line editor (TextArea), which also
// inserts the new line. The icon is passed to the input method as Qt Quick's
// EnterKey.type (Qt::ImEnterKeyType) on the attachee's editor (`_editor` of
// Silica's TextField/TextArea), which is what a Qt 6 virtual keyboard reads;
// whether the Sailfish keyboard honours it through keel-shell is a device
// question (keel/README.md).
#ifndef KEEL_ENTERKEY_H
#define KEEL_ENTERKEY_H

#include <QObject>
#include <QPointer>
#include <QQuickWindow>
#include <QString>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class KeelEnterKeyAttached : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool highlighted READ highlighted WRITE setHighlighted NOTIFY highlightedChanged)
    Q_PROPERTY(QUrl iconSource READ iconSource WRITE setIconSource NOTIFY iconSourceChanged)
    Q_PROPERTY(QString text READ text WRITE setText NOTIFY textChanged)
    // Qt::EnterKeyType derived from iconSource (Keel extension, read-only).
    Q_PROPERTY(int enterKeyType READ enterKeyType NOTIFY iconSourceChanged)

public:
    explicit KeelEnterKeyAttached(QObject *parent = nullptr);

    bool enabled() const { return m_enabled; }
    void setEnabled(bool v);
    bool highlighted() const { return m_highlighted; }
    void setHighlighted(bool v);
    QUrl iconSource() const { return m_iconSource; }
    void setIconSource(const QUrl &v);
    QString text() const { return m_text; }
    void setText(const QString &v);
    int enterKeyType() const;

signals:
    void enabledChanged();
    void highlightedChanged();
    void iconSourceChanged();
    void textChanged();
    void clicked();

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void updateInputMethod();
    void watchWindow();
    QPointer<QQuickWindow> m_window;

    bool m_enabled = true;
    bool m_highlighted = false;
    QUrl m_iconSource;
    QString m_text;
};

class KeelEnterKey : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(EnterKey)
    QML_UNCREATABLE("EnterKey is an attached property")
    QML_ATTACHED(KeelEnterKeyAttached)

public:
    static KeelEnterKeyAttached *qmlAttachedProperties(QObject *object);
};

// Internal helper for Keel's own QML: in expressions, Qt 6 resolves the name
// `EnterKey` to Qt Quick's attached type (QtQuick >= 2.6 is searched first),
// so TextField/TextArea fetch Silica's attached object through this.
class KeelEnterKeyHelper : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(KeelEnterKeyHelper)
    QML_SINGLETON

public:
    explicit KeelEnterKeyHelper(QObject *parent = nullptr) : QObject(parent) { }
    Q_INVOKABLE KeelEnterKeyAttached *attachedTo(QObject *item) const;
};

#endif // KEEL_ENTERKEY_H
