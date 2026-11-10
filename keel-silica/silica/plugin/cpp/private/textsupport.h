// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Native helpers of Silica's BSD text editors (TextField.qml, TextArea.qml,
// private/TextBase.qml); names inferred from that QML. Clean-room.
//
// ProxyValidator: `validator`, `strictValidation`. Validates with
//   `validator`; unless strictValidation, input the validator rejects is
//   still accepted as intermediate, so it can be typed and is shown as an
//   error (acceptableInput false) rather than refused.
// PreeditText: a child of a TextInput/TextEdit; `text` is the editor's text
//   with the input method's uncommitted pre-edit text at the cursor, and
//   writing it sets the editor's text.
// VerticalAutoScroll / HorizontalAutoScroll (attached): keep the
//   `cursorRectangle` of the attachee (item coordinates) visible in the
//   nearest ancestor Flickable, inside `topMargin`/`bottomMargin` (or
//   `leftMargin`/`rightMargin`), whenever it or the geometry changes and on
//   fixup(); `keepVisible` (default true) enables it; `animated` scrolls
//   with an animation; with `restorePosition` the flickable returns to where
//   it was when keepVisible goes false. `modal` is accepted (Keel's
//   flickables never scroll other content away under a modal item).
#ifndef KEEL_TEXTSUPPORT_H
#define KEEL_TEXTSUPPORT_H

#include <QPointer>
#include <QPropertyAnimation>
#include <QQmlParserStatus>
#include <QQuickItem>
#include <QRectF>
#include <QValidator>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class KeelProxyValidator : public QValidator
{
    Q_OBJECT
    QML_NAMED_ELEMENT(ProxyValidator)
    Q_PROPERTY(QValidator *validator READ validator WRITE setValidator NOTIFY validatorChanged)
    Q_PROPERTY(bool strictValidation READ strictValidation WRITE setStrictValidation NOTIFY strictValidationChanged)

public:
    explicit KeelProxyValidator(QObject *parent = nullptr);

    QValidator *validator() const { return m_validator; }
    void setValidator(QValidator *validator);
    bool strictValidation() const { return m_strict; }
    void setStrictValidation(bool strict);

    State validate(QString &input, int &pos) const override;
    void fixup(QString &input) const override;

signals:
    void validatorChanged();
    void strictValidationChanged();

private:
    QPointer<QValidator> m_validator;
    bool m_strict = false;
};

class KeelPreeditText : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    Q_INTERFACES(QQmlParserStatus)
    QML_NAMED_ELEMENT(PreeditText)
    Q_PROPERTY(QString text READ text WRITE setText NOTIFY textChanged)

public:
    explicit KeelPreeditText(QObject *parent = nullptr);

    QString text() const;
    void setText(const QString &text);

    void classBegin() override;
    void componentComplete() override;

signals:
    void textChanged();

private slots:
    void editorChanged();

private:
    QObject *editor() const { return parent(); }
    // Connects to the editor as soon as it is known (the QML engine sets the
    // parent before classBegin()): bindings read `text` before
    // componentComplete(), and must be told about every later change.
    bool ensureConnected();
    QPointer<QObject> m_connected;
    QString m_last;
};

class KeelAutoScrollAttached : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool keepVisible READ keepVisible WRITE setKeepVisible NOTIFY keepVisibleChanged)
    Q_PROPERTY(QVariant cursorRectangle READ cursorRectangle WRITE setCursorRectangle NOTIFY cursorRectangleChanged)
    Q_PROPERTY(bool animated READ animated WRITE setAnimated NOTIFY animatedChanged)
    Q_PROPERTY(bool modal READ modal WRITE setModal NOTIFY modalChanged)
    Q_PROPERTY(bool restorePosition READ restorePosition WRITE setRestorePosition NOTIFY restorePositionChanged)
    Q_PROPERTY(qreal topMargin READ topMargin WRITE setTopMargin NOTIFY topMarginChanged)
    Q_PROPERTY(qreal bottomMargin READ bottomMargin WRITE setBottomMargin NOTIFY bottomMarginChanged)
    Q_PROPERTY(qreal leftMargin READ leftMargin WRITE setLeftMargin NOTIFY leftMarginChanged)
    Q_PROPERTY(qreal rightMargin READ rightMargin WRITE setRightMargin NOTIFY rightMarginChanged)

public:
    KeelAutoScrollAttached(QObject *attachee, Qt::Orientation orientation);

    bool keepVisible() const { return m_keepVisible; }
    void setKeepVisible(bool keep);
    QVariant cursorRectangle() const { return m_rectSet ? QVariant(m_rect) : QVariant(); }
    void setCursorRectangle(const QVariant &rect);
    bool animated() const { return m_animated; }
    void setAnimated(bool a) { if (a != m_animated) { m_animated = a; emit animatedChanged(); } }
    bool modal() const { return m_modal; }
    void setModal(bool m) { if (m != m_modal) { m_modal = m; emit modalChanged(); } }
    bool restorePosition() const { return m_restore; }
    void setRestorePosition(bool r) { if (r != m_restore) { m_restore = r; emit restorePositionChanged(); } }
    qreal topMargin() const { return m_margins[0]; }
    void setTopMargin(qreal m) { setMargin(0, m, &KeelAutoScrollAttached::topMarginChanged); }
    qreal bottomMargin() const { return m_margins[1]; }
    void setBottomMargin(qreal m) { setMargin(1, m, &KeelAutoScrollAttached::bottomMarginChanged); }
    qreal leftMargin() const { return m_margins[2]; }
    void setLeftMargin(qreal m) { setMargin(2, m, &KeelAutoScrollAttached::leftMarginChanged); }
    qreal rightMargin() const { return m_margins[3]; }
    void setRightMargin(qreal m) { setMargin(3, m, &KeelAutoScrollAttached::rightMarginChanged); }

    Q_INVOKABLE void fixup();

signals:
    void keepVisibleChanged();
    void cursorRectangleChanged();
    void animatedChanged();
    void modalChanged();
    void restorePositionChanged();
    void topMarginChanged();
    void bottomMarginChanged();
    void leftMarginChanged();
    void rightMarginChanged();

private:
    void setMargin(int i, qreal m, void (KeelAutoScrollAttached::*notify)())
    {
        if (qFuzzyCompare(m_margins[i] + 1, m + 1))
            return;
        m_margins[i] = m;
        emit(this->*notify)();
        scheduleFixup();
    }
    QQuickItem *findFlickable() const;
    void scheduleFixup();

    QPointer<QQuickItem> m_item;
    QPointer<QQuickItem> m_restoreFlickable;
    QPointer<QPropertyAnimation> m_animation;
    Qt::Orientation m_orientation;
    QRectF m_rect;
    bool m_rectSet = false;
    bool m_keepVisible = true;
    bool m_animated = true;
    bool m_modal = false;
    bool m_restore = false;
    bool m_pending = false;
    qreal m_restoreValue = 0;
    qreal m_margins[4] = {};
};

class KeelVerticalAutoScroll : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(VerticalAutoScroll)
    QML_UNCREATABLE("VerticalAutoScroll is an attached property")
    QML_ATTACHED(KeelAutoScrollAttached)

public:
    static KeelAutoScrollAttached *qmlAttachedProperties(QObject *object)
    {
        return new KeelAutoScrollAttached(object, Qt::Vertical);
    }
};

class KeelHorizontalAutoScroll : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(HorizontalAutoScroll)
    QML_UNCREATABLE("HorizontalAutoScroll is an attached property")
    QML_ATTACHED(KeelAutoScrollAttached)

public:
    static KeelAutoScrollAttached *qmlAttachedProperties(QObject *object)
    {
        return new KeelAutoScrollAttached(object, Qt::Horizontal);
    }
};

#endif // KEEL_TEXTSUPPORT_H
