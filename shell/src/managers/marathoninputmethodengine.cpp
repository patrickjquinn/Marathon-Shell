#include "marathoninputmethodengine.h"
#include "marathon-shell-native/src/device.cxxqt.h"
#include "marathon-shell-native/src/settings.cxxqt.h"
#include <QDebug>
#include <QGuiApplication>
#include <QInputMethod>
#include <QInputMethodEvent>
#include <QInputMethodQueryEvent>
#include <QKeyEvent>

MarathonInputMethodEngine::MarathonInputMethodEngine(const marathon::Settings *settings,
                                                     QObject                  *parent)
    : QObject(parent)
    , m_active(false)
    , m_preeditText("")
    , m_inputMethod(nullptr)
    , m_settings(settings) {
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

// A hardware keyboard's first letter of a sentence, typed as a capital the
// way the on-screen keyboard shifts for it (and BlackBerry's keyboards did).
bool MarathonInputMethodEngine::capitalise(QObject *obj, const QKeyEvent *key) {
    const bool held = m_heldCapital != 0 && key->nativeScanCode() == m_heldCapital;
    if (key->type() == QEvent::KeyRelease || key->isAutoRepeat()) {
        if (held && key->type() == QEvent::KeyRelease && !key->isAutoRepeat())
            m_heldCapital = 0;
        return held;
    }
    const QString text = key->text();
    if (text.size() != 1 || !text.front().isLower() || (key->modifiers() & ~Qt::KeypadModifier) ||
        !m_settings->getKeyboardAutoCapitalize()) {
        if (text.isEmpty() || !text.front().isPrint())
            m_capitalisedAt.clear();
        return false;
    }
    QInputMethodQueryEvent query(Qt::ImEnabled | Qt::ImHints | Qt::ImSurroundingText |
                                 Qt::ImCursorPosition);
    QGuiApplication::sendEvent(obj, &query);
    // The fields the on-screen keyboard leaves lower case (MarathonKeyboard.qml).
    constexpr Qt::InputMethodHints plain = Qt::ImhNoAutoUppercase | Qt::ImhNoPredictiveText |
        Qt::ImhSensitiveData | Qt::ImhHiddenText | Qt::ImhUrlCharactersOnly |
        Qt::ImhEmailCharactersOnly | Qt::ImhDigitsOnly | Qt::ImhFormattedNumbersOnly |
        Qt::ImhDialableCharactersOnly;
    if (!query.value(Qt::ImEnabled).toBool() ||
        (Qt::InputMethodHints(query.value(Qt::ImHints).toInt()) & plain))
        return false;
    const QString before   = query.value(Qt::ImSurroundingText)
                                 .toString()
                                 .left(query.value(Qt::ImCursorPosition).toInt());
    const QString sentence = before.trimmed();
    const bool    start    = sentence.isEmpty() ||
        (before.back().isSpace() && QStringView(u".!?").contains(sentence.back()));
    if (!start || before == m_capitalisedAt)
        return false;
    QInputMethodEvent commit;
    commit.setCommitString(text.toUpper());
    QGuiApplication::sendEvent(obj, &commit);
    m_capitalisedAt = before;
    m_heldCapital   = key->nativeScanCode();
    return true;
}

bool MarathonInputMethodEngine::eventFilter(QObject *obj, QEvent *event) {
    if ((event->type() == QEvent::KeyPress || event->type() == QEvent::KeyRelease) &&
        event->spontaneous() && obj == QGuiApplication::focusObject() &&
        capitalise(obj, static_cast<QKeyEvent *>(event)))
        return true;
    if (event->type() == QEvent::FocusIn) {

        QInputMethodQueryEvent query(Qt::ImEnabled | Qt::ImHints);
        QGuiApplication::sendEvent(obj, &query);

        if (query.value(Qt::ImEnabled).toBool()) {
            qDebug() << "[InputEngine] FocusIn detected on:" << obj
                     << "HW Keyboard:" << marathon::device::has_hardware_keyboard();

            if (!marathon::device::has_hardware_keyboard()) {

                showKeyboard(true);
                emit inputItemFocused();
            }
        }
    }
    return QObject::eventFilter(obj, event);
}
