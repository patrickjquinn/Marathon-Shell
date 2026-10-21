#include "remotetextinput.h"

#include "marathon-shell-native/src/text_input.cxxqt.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QInputDevice>
#include <QInputMethodEvent>
#include <QInputMethodQueryEvent>
#include <QKeyEvent>
#include <QQuickItem>

#include <algorithm>

namespace {
    // zwp_text_input_v3
    enum Purpose : quint8 {
        Alpha    = 1,
        Digits   = 2,
        Number   = 3,
        Phone    = 4,
        Url      = 5,
        Email    = 6,
        Password = 8,
        Pin      = 9,
        Date     = 10,
        Time     = 11,
        DateTime = 12,
    };
    enum Hint : quint16 {
        Completion         = 0x1,
        AutoCapitalization = 0x4,
        Lowercase          = 0x8,
        Uppercase          = 0x10,
        Titlecase          = 0x20,
        HiddenText         = 0x40,
        SensitiveData      = 0x80,
        Latin              = 0x100,
        Multiline          = 0x200,
    };

    QString keyName(int key) {
        switch (key) {
            case Qt::Key_Backspace: return QStringLiteral("backspace");
            case Qt::Key_Return:
            case Qt::Key_Enter: return QStringLiteral("enter");
            case Qt::Key_Left: return QStringLiteral("left");
            case Qt::Key_Right: return QStringLiteral("right");
            case Qt::Key_Up: return QStringLiteral("up");
            case Qt::Key_Down: return QStringLiteral("down");
            case Qt::Key_Tab: return QStringLiteral("tab");
            case Qt::Key_Escape: return QStringLiteral("escape");
            default: return {};
        }
    }
} // namespace

RemoteTextInputFilter::RemoteTextInputFilter(RemoteTextInput *input, AppIdOf appIdOf, QObject *parent)
    : QObject(parent)
    , m_input(input)
    , m_appIdOf(std::move(appIdOf)) {
    QCoreApplication::instance()->installEventFilter(this);
}

RemoteTextInputFilter::~RemoteTextInputFilter() {
    if (QCoreApplication::instance())
        QCoreApplication::instance()->removeEventFilter(this);
}

// Qt's own text-input v3 mapping (qwaylandtextinputv3.cpp), so an app's
// field reads the same to the keyboard whichever way it arrives.
Qt::InputMethodHints RemoteTextInputFilter::qtHints(uint purpose, uint hints) {
    Qt::InputMethodHints out;
    if (!(hints & Completion))
        out |= Qt::ImhNoPredictiveText;
    if (!(hints & AutoCapitalization))
        out |= Qt::ImhNoAutoUppercase;
    if (hints & Lowercase)
        out |= Qt::ImhPreferLowercase;
    if (hints & (Uppercase | Titlecase))
        out |= Qt::ImhPreferUppercase;
    if (hints & HiddenText)
        out |= Qt::ImhHiddenText;
    if (hints & SensitiveData)
        out |= Qt::ImhSensitiveData;
    if (hints & Latin)
        out |= Qt::ImhLatinOnly;
    if (hints & Multiline)
        out |= Qt::ImhMultiLine;
    switch (purpose) {
        case Alpha: out |= Qt::ImhUppercaseOnly | Qt::ImhLowercaseOnly; break;
        case Digits:
        case Pin: out |= Qt::ImhDigitsOnly; break;
        case Number: out |= Qt::ImhFormattedNumbersOnly; break;
        case Phone: out |= Qt::ImhDialableCharactersOnly; break;
        case Url: out |= Qt::ImhUrlCharactersOnly; break;
        case Email: out |= Qt::ImhEmailCharactersOnly; break;
        case Password: out |= Qt::ImhHiddenText | Qt::ImhSensitiveData; break;
        case Date: out |= Qt::ImhDate; break;
        case Time: out |= Qt::ImhTime; break;
        case DateTime: out |= Qt::ImhDate | Qt::ImhTime; break;
        default: break;
    }
    return out;
}

// The editor's window, or, while Qt's focus is on no window and no text field
// of the shell's, the app in front.
bool RemoteTextInputFilter::targets(QObject *object) const {
    const QString editor = m_input->editorAppId();
    if (!object || editor.isEmpty())
        return false;
    const QString appId = m_appIdOf ? m_appIdOf(object) : QString();
    if (!appId.isEmpty())
        return appId == editor;
    auto *item = qobject_cast<QQuickItem *>(object);
    if (item && item->flags().testFlag(QQuickItem::ItemAcceptsInputMethod))
        return false;
    return m_input->getFrontAppId() == editor;
}

bool RemoteTextInputFilter::targetsFocus() const {
    return targets(QGuiApplication::focusObject());
}

QVariant RemoteTextInputFilter::query(Qt::InputMethodQuery query) const {
    const QString text   = m_input->editorText();
    const int     cursor = m_input->editorCursor();
    const int     anchor = m_input->editorAnchor();
    const int     from   = std::min(cursor, anchor);
    switch (query) {
        case Qt::ImEnabled: return true;
        case Qt::ImHints: return int(qtHints(m_input->editorPurpose(), m_input->editorHints()));
        case Qt::ImSurroundingText: return text;
        case Qt::ImCursorPosition: return cursor;
        case Qt::ImAnchorPosition: return anchor;
        case Qt::ImTextBeforeCursor: return text.left(cursor);
        case Qt::ImTextAfterCursor: return text.mid(cursor);
        case Qt::ImCurrentSelection: return text.mid(from, std::max(cursor, anchor) - from);
        default: return {};
    }
}

// Replacements reach the service as counts around the cursor; any other
// range would need a selection protocol nobody sends.
void RemoteTextInputFilter::commit(const QInputMethodEvent &event) {
    const QString &text   = event.commitString();
    int            before = 0;
    int            after  = 0;
    const int      start  = event.replacementStart();
    const int      length = event.replacementLength();
    if (length > 0 && start <= 0 && start + length >= 0) {
        before = -start;
        after  = start + length;
    }
    if (text.isEmpty() && before == 0 && after == 0)
        return;
    m_input->commit(text, before, after);
}

bool RemoteTextInputFilter::eventFilter(QObject *watched, QEvent *event) {
    switch (event->type()) {
        case QEvent::InputMethodQuery: {
            if (!targets(watched))
                break;
            auto *query = static_cast<QInputMethodQueryEvent *>(event);
            for (uint bit = 1; bit && bit <= Qt::ImReadOnly; bit <<= 1) {
                const auto q = Qt::InputMethodQuery(bit);
                if (query->queries() & q)
                    query->setValue(q, this->query(q));
            }
            query->accept();
            return true;
        }
        case QEvent::InputMethod:
            if (!targets(watched))
                break;
            commit(*static_cast<QInputMethodEvent *>(event));
            event->accept();
            return true;
        case QEvent::KeyPress:
        case QEvent::KeyRelease: {
            auto *key = static_cast<QKeyEvent *>(event);
            if (!key->device() || key->device()->name() != kKeyboardDevice || !targets(watched))
                break;
            const QString name = keyName(key->key());
            if (name.isEmpty())
                break;
            if (event->type() == QEvent::KeyPress)
                m_input->key(name);
            event->accept();
            return true;
        }
        default: break;
    }
    return QObject::eventFilter(watched, event);
}
