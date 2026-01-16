#include "marathoninputmethodengine.h"
#include "platform.h"
#include <QDebug>
#include <QGuiApplication>
#include <QInputMethod>
#include <QInputMethodQueryEvent>
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

static int charToKey(QChar ch) {
    if (ch.isLetter()) {
        return Qt::Key_A + (ch.toUpper().unicode() - 'A');
    }
    if (ch.isDigit()) {
        return Qt::Key_0 + (ch.unicode() - '0');
    }
    switch (ch.unicode()) {
        case ' ': return Qt::Key_Space;
        case '\n': return Qt::Key_Return;
        case '\t': return Qt::Key_Tab;
        case '.': return Qt::Key_Period;
        case ',': return Qt::Key_Comma;
        case ';': return Qt::Key_Semicolon;
        case ':': return Qt::Key_Colon;
        case '\'': return Qt::Key_Apostrophe;
        case '"': return Qt::Key_QuoteDbl;
        case '!': return Qt::Key_Exclam;
        case '?': return Qt::Key_Question;
        case '@': return Qt::Key_At;
        case '#': return Qt::Key_NumberSign;
        case '$': return Qt::Key_Dollar;
        case '%': return Qt::Key_Percent;
        case '^': return Qt::Key_AsciiCircum;
        case '&': return Qt::Key_Ampersand;
        case '*': return Qt::Key_Asterisk;
        case '(': return Qt::Key_ParenLeft;
        case ')': return Qt::Key_ParenRight;
        case '-': return Qt::Key_Minus;
        case '_': return Qt::Key_Underscore;
        case '=': return Qt::Key_Equal;
        case '+': return Qt::Key_Plus;
        case '[': return Qt::Key_BracketLeft;
        case ']': return Qt::Key_BracketRight;
        case '{': return Qt::Key_BraceLeft;
        case '}': return Qt::Key_BraceRight;
        case '\\': return Qt::Key_Backslash;
        case '|': return Qt::Key_Bar;
        case '/': return Qt::Key_Slash;
        case '`': return Qt::Key_QuoteLeft;
        case '~': return Qt::Key_AsciiTilde;
        case '<': return Qt::Key_Less;
        case '>': return Qt::Key_Greater;
        default: return 0;
    }
}

void MarathonInputMethodEngine::commitText(const QString &text) {
    if (!m_inputMethod)
        return;

    for (const QChar &ch : text) {
        int                   key  = charToKey(ch);
        Qt::KeyboardModifiers mods = Qt::NoModifier;

        if (ch.isLetter() && ch.isUpper()) {
            mods |= Qt::ShiftModifier;
        }

        QKeyEvent *pressEvent   = new QKeyEvent(QEvent::KeyPress, key, mods, QString(ch));
        QKeyEvent *releaseEvent = new QKeyEvent(QEvent::KeyRelease, key, mods, QString(ch));

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

void MarathonInputMethodEngine::onInputMethodAnimatingChanged() {}

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
