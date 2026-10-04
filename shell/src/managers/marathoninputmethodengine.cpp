#include "marathoninputmethodengine.h"
#include "platform.h"
#include <QDebug>
#include <QGuiApplication>
#include <QInputMethod>
#include <QInputMethodQueryEvent>
#include <QInputMethodEvent>
#include <QKeyEvent>

MarathonInputMethodEngine::MarathonInputMethodEngine(QObject *parent)
    : QObject(parent)
    , m_active(false)
    , m_preeditText("")
    , m_inputMethod(nullptr) {
    m_inputMethod = QGuiApplication::inputMethod();
    if (m_inputMethod) {
        connectToInputMethod();
    }

    QCoreApplication::instance()->installEventFilter(this);
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

// Text goes in as an input-method commit, not as key events. A synthetic
// QKeyEvent carries no native scan code, so when the focus object is an app's
// surface item the compositor forwarded it to the client as keycode 0 and the
// app typed nothing. A commit reaches in-shell text fields directly and
// reaches apps through text-input (QWaylandQuickItem forwards it).
void MarathonInputMethodEngine::commitText(const QString &text) {
    QObject *focus = QGuiApplication::focusObject();
    if (!focus || text.isEmpty())
        return;

    QInputMethodEvent event;
    event.setCommitString(text);
    QGuiApplication::sendEvent(focus, &event);

    if (!m_preeditText.isEmpty()) {
        m_preeditText.clear();
        emit preeditTextChanged();
    }
}

// Backspace and Enter stay key events, but with the scan code and keysym a
// real keyboard would send, so the compositor can forward them to apps.
// Scan codes are evdev codes plus the XKB offset of 8.
static void sendKey(Qt::Key key, quint32 scanCode, quint32 keysym, const QString &text) {
    QObject *focus = QGuiApplication::focusObject();
    if (!focus)
        return;
    QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier, scanCode, keysym, 0, text);
    QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier, scanCode, keysym, 0, text);
    QGuiApplication::sendEvent(focus, &press);
    QGuiApplication::sendEvent(focus, &release);
}

void MarathonInputMethodEngine::sendBackspace() {
    sendKey(Qt::Key_Backspace, 14 + 8, 0xff08 /* XKB_KEY_BackSpace */, QString());
}

void MarathonInputMethodEngine::sendEnter() {
    // No text: Qt's seat sends a key with text to text-input-v3 clients as a
    // commit of "\r", which GTK inserts instead of activating the field.
    sendKey(Qt::Key_Return, 28 + 8, 0xff0d /* XKB_KEY_Return */, QString());
}

void MarathonInputMethodEngine::replacePreedit(const QString &word) {
    if (!m_preeditText.isEmpty()) {
        for (int i = 0; i < m_preeditText.length(); ++i) {
            sendBackspace();
        }
    }
    commitText(word);
}

QString MarathonInputMethodEngine::getTextBeforeCursor(int length) {
    QObject *focusObject = QGuiApplication::focusObject();
    if (!focusObject)
        return QString();

    QInputMethodQueryEvent query(Qt::ImSurroundingText | Qt::ImCursorPosition);
    QGuiApplication::sendEvent(focusObject, &query);

    QString text   = query.value(Qt::ImSurroundingText).toString();
    int     cursor = query.value(Qt::ImCursorPosition).toInt();

    return text.left(cursor).right(length);
}

QString MarathonInputMethodEngine::getTextAfterCursor(int length) {
    QObject *focusObject = QGuiApplication::focusObject();
    if (!focusObject)
        return QString();

    QInputMethodQueryEvent query(Qt::ImSurroundingText | Qt::ImCursorPosition);
    QGuiApplication::sendEvent(focusObject, &query);

    QString text   = query.value(Qt::ImSurroundingText).toString();
    int     cursor = query.value(Qt::ImCursorPosition).toInt();

    return text.mid(cursor, length);
}

QString MarathonInputMethodEngine::getCurrentWord() {
    return m_preeditText;
}

void MarathonInputMethodEngine::showKeyboard(bool show) {
    if (!m_inputMethod)
        return;

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

    if (visible) {
        emit inputItemFocused();
    } else {
        emit inputItemUnfocused();
    }

    emit hasActiveFocusChanged();
}

void MarathonInputMethodEngine::onCursorRectangleChanged() {
    emit cursorPositionChanged();
    emit inputItemRectChanged();
}

bool MarathonInputMethodEngine::eventFilter(QObject *obj, QEvent *event) {
    if (event->type() == QEvent::FocusIn) {

        QInputMethodQueryEvent query(Qt::ImEnabled | Qt::ImHints);
        QGuiApplication::sendEvent(obj, &query);

        if (query.value(Qt::ImEnabled).toBool()) {
            qDebug() << "[InputEngine] FocusIn detected on:" << obj
                     << "HW Keyboard:" << Platform::hasHardwareKeyboard();

            if (!Platform::hasHardwareKeyboard()) {

                showKeyboard(true);
                emit inputItemFocused();
            }
        }
    }
    return QObject::eventFilter(obj, event);
}
