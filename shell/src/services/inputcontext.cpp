#include "inputcontext.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QInputMethod>
#include <QInputMethodEvent>
#include <QInputMethodQueryEvent>
#include <QKeyEvent>

namespace {
    // Text and replacements go in as input-method events: they reach the
    // shell's own fields directly and app surfaces through text-input, where a
    // replacement becomes delete_surrounding_text plus commit_string.
    void sendCommit(const QString &text, int replaceFrom = 0, int replaceLength = 0) {
        QObject *focus = QGuiApplication::focusObject();
        if (!focus)
            return;
        QInputMethodEvent event;
        event.setCommitString(text, replaceFrom, replaceLength);
        QGuiApplication::sendEvent(focus, &event);
    }

    // A synthetic key needs the scan code and keysym a real keyboard sends, or
    // the compositor forwards it to apps as keycode 0. Scan codes are evdev
    // codes plus the XKB offset of 8.
    void sendKey(Qt::Key key, quint32 scanCode, quint32 keysym) {
        QObject *focus = QGuiApplication::focusObject();
        if (!focus)
            return;
        QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier, scanCode, keysym, 0);
        QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier, scanCode, keysym, 0);
        QGuiApplication::sendEvent(focus, &press);
        QGuiApplication::sendEvent(focus, &release);
    }

    // What the field reports before its cursor, or nothing when it reports no
    // surrounding text or has a selection: the keyboard then never deletes.
    QString textBeforeCursor() {
        QObject *focus = QGuiApplication::focusObject();
        if (!focus)
            return {};
        QInputMethodQueryEvent query(Qt::ImTextBeforeCursor | Qt::ImCurrentSelection);
        QGuiApplication::sendEvent(focus, &query);
        if (!query.value(Qt::ImCurrentSelection).toString().isEmpty())
            return {};
        return query.value(Qt::ImTextBeforeCursor).toString();
    }
} // namespace

InputContext::InputContext(QObject *parent)
    : QObject(parent) {
    m_inputMethod = QGuiApplication::inputMethod();
    if (m_inputMethod) {
        connect(m_inputMethod, &QInputMethod::visibleChanged, this, [this]() {
            emit hasActiveFocusChanged();
            if (m_inputMethod->isVisible()) {
                detectInputMode();
            }
        });
    }

    auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance());
    if (app) {
        connect(app, &QGuiApplication::focusObjectChanged, this,
                [this](QObject *) { detectInputMode(); });
    }
}

void InputContext::setKeyboard(QObject *keyboard) {
    if (m_keyboard == keyboard) {
        return;
    }
    m_keyboard = keyboard;
    emit keyboardChanged();
}

void InputContext::setInputMode(const QString &mode) {
    setInputModeInternal(mode);
}

QString InputContext::recommendedLayout() const {
    if (m_inputMode == "email") {
        return "email";
    }
    if (m_inputMode == "url") {
        return "url";
    }
    if (m_inputMode == "number") {
        return "number";
    }
    if (m_inputMode == "phone") {
        return "phone";
    }
    if (m_inputMode == "terminal") {
        return "terminal";
    }
    return "dynamic";
}

bool InputContext::autoCapitalizeEnabled() const {
    return m_autoCapitalizeEnabled;
}

void InputContext::setAutoCapitalizeEnabled(bool enabled) {
    if (m_autoCapitalizeEnabled == enabled) {
        return;
    }
    m_autoCapitalizeEnabled = enabled;
    emit inputModeChanged();
}

bool InputContext::autoCorrectEnabled() const {
    return m_autoCorrectEnabled;
}

void InputContext::setAutoCorrectEnabled(bool enabled) {
    if (m_autoCorrectEnabled == enabled) {
        return;
    }
    m_autoCorrectEnabled = enabled;
    emit inputModeChanged();
}

bool InputContext::predictionsEnabled() const {
    return m_predictionsEnabled;
}

void InputContext::setPredictionsEnabled(bool enabled) {
    if (m_predictionsEnabled == enabled) {
        return;
    }
    m_predictionsEnabled = enabled;
    emit inputModeChanged();
}

bool InputContext::shouldAutoCapitalize() const {
    if (!m_autoCapitalizeEnabled) {
        return false;
    }
    return !(m_inputMode == "email" || m_inputMode == "url" || m_inputMode == "number" ||
             m_inputMode == "phone" || m_inputMode == "terminal");
}

bool InputContext::shouldAutoCorrect() const {
    if (!m_autoCorrectEnabled) {
        return false;
    }
    return !(m_inputMode == "email" || m_inputMode == "url" || m_inputMode == "number" ||
             m_inputMode == "phone" || m_inputMode == "terminal");
}

bool InputContext::shouldShowPredictions() const {
    if (!m_predictionsEnabled) {
        return false;
    }
    if (m_inputMode == "number" || m_inputMode == "phone" || m_inputMode == "terminal") {
        return false;
    }
    return true;
}

bool InputContext::hasActiveFocus() const {
    return m_inputMethod && m_inputMethod->isVisible();
}

void InputContext::insertText(const QString &text) {
    if (text.isEmpty())
        return;
    sendCommit(text);
    emit textInserted(text);
}

void InputContext::handleBackspace() {
    sendKey(Qt::Key_Backspace, 14 + 8, 0xff08 /* XKB_KEY_BackSpace */);
    emit backspacePressed();
}

// No text: Qt's seat sends a key with text to text-input-v3 clients as a
// commit of "\r", which GTK inserts instead of activating the field.
void InputContext::handleEnter() {
    sendKey(Qt::Key_Return, 28 + 8, 0xff0d /* XKB_KEY_Return */);
    emit enterPressed();
}

void InputContext::sendCursorKey(int key) {
    emit cursorKeyPressed(key);
}

// Replaces text only when the field confirms it sits right before the cursor,
// so the keyboard never deletes what it did not type: the user may have moved
// the cursor or typed on a hardware keyboard since.
bool InputContext::replaceTextBeforeCursor(const QString &before, const QString &text) {
    if (before.isEmpty() || !textBeforeCursor().endsWith(before))
        return false;
    sendCommit(text, -int(before.size()), int(before.size()));
    return true;
}

// The current word must also start at a word boundary in the field.
bool InputContext::replaceCurrentWord(const QString &newWord) const {
    const QString word   = getCurrentWord();
    const QString before = textBeforeCursor();
    if (word.isEmpty() || !before.endsWith(word))
        return false;
    const qsizetype start = before.size() - word.size();
    if (start > 0 && before.at(start - 1).isLetterOrNumber())
        return false;
    sendCommit(newWord, -int(word.size()), int(word.size()));
    return true;
}

// The second space of a double tap becomes ". " when it follows a word, as on
// Android and iOS; after another space or punctuation it stays a space.
bool InputContext::insertDoubleSpacePeriod() {
    const QString before = textBeforeCursor();
    if (before.size() < 2 || !before.endsWith(u' '))
        return false;
    const QChar last = before.at(before.size() - 2);
    if (!last.isLetterOrNumber() && !QStringView(u")]}\"'\u201d\u2019\u00bb").contains(last))
        return false;
    sendCommit(QStringLiteral(". "), -1, 1);
    return true;
}

// An empty field or text ending a sentence; false when the field reports no
// text, so the keyboard keeps the shift its own punctuation set.
bool InputContext::atSentenceStart() const {
    QObject *focus = QGuiApplication::focusObject();
    if (!focus)
        return false;
    QInputMethodQueryEvent query(Qt::ImTextBeforeCursor);
    QGuiApplication::sendEvent(focus, &query);
    const QVariant value = query.value(Qt::ImTextBeforeCursor);
    if (!value.isValid())
        return false;
    const QString before = value.toString().trimmed();
    return before.isEmpty() || QStringView(u".!?").contains(before.back());
}

QString InputContext::getCurrentWord() const {
    if (!m_keyboard) {
        return {};
    }
    const QVariant value = m_keyboard->property("currentWord");
    return value.toString();
}

void InputContext::detectInputMode() {
    if (!m_inputMethod) {
        setInputModeInternal("text");
        return;
    }

    const QVariant             hintValue = QInputMethod::queryFocusObject(Qt::ImHints, QVariant());
    const Qt::InputMethodHints hints     = static_cast<Qt::InputMethodHints>(hintValue.toInt());
    if (hints & Qt::ImhEmailCharactersOnly) {
        setInputModeInternal("email");
    } else if (hints & Qt::ImhUrlCharactersOnly) {
        // Only the explicit hint: GTK's plain entries arrive over
        // text-input-v3 as no-autocaps + no-prediction, which isn't a URL.
        setInputModeInternal("url");
    } else if (hints & Qt::ImhDigitsOnly) {
        setInputModeInternal("number");
    } else if (hints & Qt::ImhDialableCharactersOnly) {
        setInputModeInternal("phone");
    } else {
        setInputModeInternal("text");
    }
}

void InputContext::setInputModeInternal(const QString &mode) {
    if (m_inputMode == mode) {
        return;
    }
    m_inputMode = mode;
    emit inputModeChanged();
}
