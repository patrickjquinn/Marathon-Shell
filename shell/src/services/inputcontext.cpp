#include "inputcontext.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QInputMethod>

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
    emit textInserted(text);
}

void InputContext::handleBackspace() {
    emit backspacePressed();
}

void InputContext::handleEnter() {
    emit enterPressed();
}

void InputContext::sendCursorKey(int key) {
    emit cursorKeyPressed(key);
}

void InputContext::replaceCurrentWord(const QString &newWord) {
    const QString currentWord = getCurrentWord();
    if (currentWord.isEmpty()) {
        insertText(newWord);
        return;
    }
    for (int i = 0; i < currentWord.length(); ++i) {
        handleBackspace();
    }
    insertText(newWord);
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
    } else if ((hints & Qt::ImhUrlCharactersOnly) ||
               ((hints & Qt::ImhNoAutoUppercase) && (hints & Qt::ImhNoPredictiveText))) {
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
