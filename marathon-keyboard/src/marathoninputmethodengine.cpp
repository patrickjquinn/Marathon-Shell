
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

    return m_inputMethod->isVisible() || m_inputMethod->inputDirection() != Qt::LayoutDirectionAuto;
}

int MarathonInputMethodEngine::cursorPosition() const {
    if (!m_inputMethod)
        return 0;

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

    for (const QChar &ch : text) {
        QKeyEvent *pressEvent = new QKeyEvent(QEvent::KeyPress, 0, Qt::NoModifier, QString(ch));

        QKeyEvent *releaseEvent = new QKeyEvent(QEvent::KeyRelease, 0, Qt::NoModifier, QString(ch));

        if (QGuiApplication::focusObject()) {
            QGuiApplication::sendEvent(QGuiApplication::focusObject(), pressEvent);
            QGuiApplication::sendEvent(QGuiApplication::focusObject(), releaseEvent);
        }

        delete pressEvent;
        delete releaseEvent;
    }

    if (!m_preeditText.isEmpty()) {
        m_preeditText.clear();
        emit preeditTextChanged();
    }
}

void MarathonInputMethodEngine::sendBackspace() {
    qDebug() << "[MarathonIME] Sending backspace";

    QKeyEvent *pressEvent = new QKeyEvent(QEvent::KeyPress, Qt::Key_Backspace, Qt::NoModifier, "");

    QKeyEvent *releaseEvent =
        new QKeyEvent(QEvent::KeyRelease, Qt::Key_Backspace, Qt::NoModifier, "");

    if (QGuiApplication::focusObject()) {
        QGuiApplication::sendEvent(QGuiApplication::focusObject(), pressEvent);
        QGuiApplication::sendEvent(QGuiApplication::focusObject(), releaseEvent);
    }

    delete pressEvent;
    delete releaseEvent;
}

void MarathonInputMethodEngine::sendEnter() {
    qDebug() << "[MarathonIME] Sending enter";

    QKeyEvent *pressEvent = new QKeyEvent(QEvent::KeyPress, Qt::Key_Return, Qt::NoModifier, "\n");

    QKeyEvent *releaseEvent =
        new QKeyEvent(QEvent::KeyRelease, Qt::Key_Return, Qt::NoModifier, "\n");

    if (QGuiApplication::focusObject()) {
        QGuiApplication::sendEvent(QGuiApplication::focusObject(), pressEvent);
        QGuiApplication::sendEvent(QGuiApplication::focusObject(), releaseEvent);
    }

    delete pressEvent;
    delete releaseEvent;
}

void MarathonInputMethodEngine::replacePreedit(const QString &word) {
    qDebug() << "[MarathonIME] Replacing preedit with:" << word;

    if (!m_preeditText.isEmpty()) {
        for (int i = 0; i < m_preeditText.length(); ++i) {
            sendBackspace();
        }
    }

    commitText(word);
}

QString MarathonInputMethodEngine::getTextBeforeCursor(int length) {

    qDebug() << "[MarathonIME] getTextBeforeCursor requested (length:" << length << ")";
    return "";
}

QString MarathonInputMethodEngine::getTextAfterCursor(int length) {

    qDebug() << "[MarathonIME] getTextAfterCursor requested (length:" << length << ")";
    return "";
}

QString MarathonInputMethodEngine::getCurrentWord() {

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
