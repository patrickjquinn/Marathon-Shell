#include "marathoninputmethodengine.h"
#include "platform.h"
#include <QDebug>
#include <QGuiApplication>
#include <QInputMethod>
#include <QInputMethodQueryEvent>

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

QString MarathonInputMethodEngine::getCurrentWord() {
    return m_preeditText;
}

int MarathonInputMethodEngine::focusHints() const {
    if (!m_inputMethod)
        return 0;
    return QInputMethod::queryFocusObject(Qt::ImHints, QVariant()).toInt();
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
