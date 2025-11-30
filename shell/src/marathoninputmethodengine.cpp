// Marathon Input Method Engine - Implementation
#include "marathoninputmethodengine.h"
#include <QGuiApplication>
#include <QInputMethod>
#include <QDebug>
#include <QKeyEvent>

MarathonInputMethodEngine::MarathonInputMethodEngine(QObject *parent)
    : QObject(parent)
    , m_active(false)
    , m_preeditText("")
    , m_inputMethod(nullptr) {
    // Get Qt's input method instance
    m_inputMethod = QGuiApplication::inputMethod();

    if (m_inputMethod) {
        connectToInputMethod();
        qDebug() << "[MarathonIME] Initialized with Qt InputMethod";
    } else {
        qWarning() << "[MarathonIME] Failed to get Qt InputMethod instance";
    }
}

MarathonInputMethodEngine::~MarathonInputMethodEngine() {
    if (m_inputMethod) {
        disconnectFromInputMethod();
    }
}

void MarathonInputMethodEngine::connectToInputMethod() {
    if (!m_inputMethod)
        return;

    // Connect to input method signals
    connect(m_inputMethod, &QInputMethod::visibleChanged, this,
            &MarathonInputMethodEngine::onInputMethodVisibleChanged);
    connect(m_inputMethod, &QInputMethod::animatingChanged, this,
            &MarathonInputMethodEngine::onInputMethodAnimatingChanged);
    connect(m_inputMethod, &QInputMethod::cursorRectangleChanged, this,
            &MarathonInputMethodEngine::onCursorRectangleChanged);
}

void MarathonInputMethodEngine::disconnectFromInputMethod() {
    if (!m_inputMethod)
        return;

    disconnect(m_inputMethod, nullptr, this, nullptr);
}

void MarathonInputMethodEngine::setActive(bool active) {
    if (m_active != active) {
        m_active = active;
        emit activeChanged();

        qDebug() << "[MarathonIME] Active state changed:" << active;
    }
}

void MarathonInputMethodEngine::setPreeditText(const QString &text) {
    if (m_preeditText != text) {
        m_preeditText = text;
        emit preeditTextChanged();
    }
}

bool MarathonInputMethodEngine::hasActiveFocus() const {
    if (!m_inputMethod)
        return false;

    // Check if there's an active input item
    return m_inputMethod->isVisible() || m_inputMethod->inputDirection() != Qt::LayoutDirectionAuto;
}

int MarathonInputMethodEngine::cursorPosition() const {
    if (!m_inputMethod)
        return 0;

    // Get cursor position from input method
    // Note: This is a simplified implementation
    // Real cursor position would need to be queried from the focused input item
    return m_inputMethod->cursorRectangle().x();
}

QRect MarathonInputMethodEngine::inputItemRect() const {
    if (!m_inputMethod)
        return QRect();

    return m_inputMethod->inputItemRectangle().toRect();
}

void MarathonInputMethodEngine::commitText(const QString &text) {
    if (!m_inputMethod) {
        qWarning() << "[MarathonIME] Cannot commit text - no input method";
        return;
    }

    qDebug() << "[MarathonIME] Committing text:" << text;

    // Qt 6 API: commit() takes no arguments
    // We need to send key events or use Qt.inputMethod.commit() from QML
    // For now, simulate typing by sending key events
    for (const QChar &ch : text) {
        QKeyEvent *pressEvent = new QKeyEvent(QEvent::KeyPress,
                                              0, // Key code (0 for text input)
                                              Qt::NoModifier, QString(ch));

        QKeyEvent *releaseEvent = new QKeyEvent(QEvent::KeyRelease, 0, Qt::NoModifier, QString(ch));

        if (QGuiApplication::focusObject()) {
            QGuiApplication::sendEvent(QGuiApplication::focusObject(), pressEvent);
            QGuiApplication::sendEvent(QGuiApplication::focusObject(), releaseEvent);
        }

        delete pressEvent;
        delete releaseEvent;
    }

    // Clear preedit
    if (!m_preeditText.isEmpty()) {
        m_preeditText.clear();
        emit preeditTextChanged();
    }
}

void MarathonInputMethodEngine::sendBackspace() {
    qDebug() << "[MarathonIME] Sending backspace";

    // Create and send a backspace key event
    QKeyEvent *pressEvent = new QKeyEvent(QEvent::KeyPress, Qt::Key_Backspace, Qt::NoModifier, "");

    QKeyEvent *releaseEvent =
        new QKeyEvent(QEvent::KeyRelease, Qt::Key_Backspace, Qt::NoModifier, "");

    // Send to the application's focused widget
    if (QGuiApplication::focusObject()) {
        QGuiApplication::sendEvent(QGuiApplication::focusObject(), pressEvent);
        QGuiApplication::sendEvent(QGuiApplication::focusObject(), releaseEvent);
    }

    delete pressEvent;
    delete releaseEvent;
}

void MarathonInputMethodEngine::sendEnter() {
    qDebug() << "[MarathonIME] Sending enter";

    // Create and send an enter key event
    QKeyEvent *pressEvent = new QKeyEvent(QEvent::KeyPress, Qt::Key_Return, Qt::NoModifier, "\n");

    QKeyEvent *releaseEvent =
        new QKeyEvent(QEvent::KeyRelease, Qt::Key_Return, Qt::NoModifier, "\n");

    // Send to the application's focused widget
    if (QGuiApplication::focusObject()) {
        QGuiApplication::sendEvent(QGuiApplication::focusObject(), pressEvent);
        QGuiApplication::sendEvent(QGuiApplication::focusObject(), releaseEvent);
    }

    delete pressEvent;
    delete releaseEvent;
}

void MarathonInputMethodEngine::replacePreedit(const QString &word) {
    qDebug() << "[MarathonIME] Replacing preedit with:" << word;

    // First, delete the current preedit text
    if (!m_preeditText.isEmpty()) {
        for (int i = 0; i < m_preeditText.length(); ++i) {
            sendBackspace();
        }
    }

    // Then commit the new word
    commitText(word);
}

QString MarathonInputMethodEngine::getTextBeforeCursor(int length) {
    // This would require querying the input item directly
    // For now, return empty - real implementation would use QInputMethodQueryEvent
    qDebug() << "[MarathonIME] getTextBeforeCursor requested (length:" << length << ")";
    return "";
}

QString MarathonInputMethodEngine::getTextAfterCursor(int length) {
    // This would require querying the input item directly
    qDebug() << "[MarathonIME] getTextAfterCursor requested (length:" << length << ")";
    return "";
}

QString MarathonInputMethodEngine::getCurrentWord() {
    // Return the current preedit text as the current word
    return m_preeditText;
}

void MarathonInputMethodEngine::showKeyboard(bool show) {
    if (!m_inputMethod)
        return;

    qDebug() << "[MarathonIME] Keyboard visibility requested:" << show;

    if (show) {
        m_inputMethod->show();
        emit keyboardRequested();
    } else {
        m_inputMethod->hide();
        emit keyboardHideRequested();
    }
}

void MarathonInputMethodEngine::onInputMethodVisibleChanged() {
    bool visible = m_inputMethod ? m_inputMethod->isVisible() : false;
    qDebug() << "[MarathonIME] Input method visibility changed:" << visible;

    if (visible) {
        emit inputItemFocused();
    } else {
        emit inputItemUnfocused();
    }

    emit hasActiveFocusChanged();
}

void MarathonInputMethodEngine::onInputMethodAnimatingChanged() {
    qDebug() << "[MarathonIME] Input method animating changed";
}

void MarathonInputMethodEngine::onCursorRectangleChanged() {
    emit cursorPositionChanged();
    emit inputItemRectChanged();
}
