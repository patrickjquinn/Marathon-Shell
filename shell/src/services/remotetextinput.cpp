#include "remotetextinput.h"
#include "../ipc/callerpid.h"

#include "../ipc/servicecaller.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
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

    // NOLINTBEGIN(bugprone-throwing-static-initialization) QStringLiteral never allocates
    const QString kPath      = QStringLiteral("/org/marathonos/Shell/TextInput");
    const QString kInterface = QStringLiteral("org.marathonos.Shell.TextInput1");
    // NOLINTEND(bugprone-throwing-static-initialization)
} // namespace

RemoteTextInput::RemoteTextInput(AppIdOf appIdOf, QObject *parent)
    : QObject(parent)
    , m_appIdOf(std::move(appIdOf)) {
    QCoreApplication::instance()->installEventFilter(this);
}

RemoteTextInput::~RemoteTextInput() {
    if (QCoreApplication::instance())
        QCoreApplication::instance()->removeEventFilter(this);
}

// Qt's own text-input v3 mapping (qwaylandtextinputv3.cpp), so an app's
// field reads the same to the keyboard whichever way it arrives.
Qt::InputMethodHints RemoteTextInput::qtHints(uint purpose, uint hints) {
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

bool RemoteTextInput::owns(const QString &appId) const {
    return !m_prefix.isEmpty() && appId.size() > m_prefix.size() && appId.startsWith(m_prefix);
}

bool RemoteTextInput::handles(const QString &appId) const {
    return owns(appId);
}

// The editor's window, or, while Qt's focus is on no window and no text field
// of the shell's, the app in front.
bool RemoteTextInput::targets(QObject *object) const {
    if (!object || m_editor.appId.isEmpty())
        return false;
    const QString appId = m_appIdOf ? m_appIdOf(object) : QString();
    if (!appId.isEmpty())
        return appId == m_editor.appId;
    auto *item = qobject_cast<QQuickItem *>(object);
    if (item && item->flags().testFlag(QQuickItem::ItemAcceptsInputMethod))
        return false;
    return m_frontAppId == m_editor.appId;
}

void RemoteTextInput::setFrontAppId(const QString &appId) {
    if (m_frontAppId == appId)
        return;
    m_frontAppId = appId;
    emit frontAppIdChanged();
}

void RemoteTextInput::setService(const QString &appIdPrefix) {
    if (m_prefix == appIdPrefix)
        return;
    m_prefix = appIdPrefix;
    m_editor = {};
    emit appIdPrefixChanged();
}

bool RemoteTextInput::setEditor(const QString &appId, uint purpose, uint hints) {
    if (!owns(appId))
        return false;
    const Qt::InputMethodHints qt      = qtHints(purpose, hints);
    const bool                 changed = m_editor.appId != appId || m_editor.hints != qt;
    m_editor                           = {appId, qt, {}, 0, 0};
    if (changed)
        emit hintsChanged();
    return true;
}

bool RemoteTextInput::setSurroundingText(const QString &appId, const QString &text, int cursor,
                                         int anchor) {
    if (!owns(appId) || appId != m_editor.appId)
        return false;
    const int size  = int(text.size());
    m_editor.text   = text;
    m_editor.cursor = std::clamp(cursor, 0, size);
    m_editor.anchor = std::clamp(anchor, 0, size);
    return true;
}

bool RemoteTextInput::clearEditor(const QString &appId) {
    if (!owns(appId))
        return false;
    if (m_editor.appId == appId)
        m_editor = {};
    return true;
}

// Shown only for the window in front; hiding needs no focus.
bool RemoteTextInput::requestPanel(const QString &appId, bool show) {
    if (!owns(appId) || appId != m_editor.appId)
        return false;
    if (show && !targets(QGuiApplication::focusObject()))
        return false;
    emit panelRequested(show);
    return true;
}

void RemoteTextInput::setPanel(const QString &appId, int covered, int height) {
    if (!owns(appId))
        return;
    covered = std::max(0, covered);
    if (appId == m_panelAppId && covered == m_covered && height == m_height)
        return;
    m_panelAppId = appId;
    m_covered    = covered;
    m_height     = height;
    emit panelChanged(appId, covered, height);
}

QVariant RemoteTextInput::query(Qt::InputMethodQuery query) const {
    const int from = std::min(m_editor.cursor, m_editor.anchor);
    const int to   = std::max(m_editor.cursor, m_editor.anchor);
    switch (query) {
        case Qt::ImEnabled: return true;
        case Qt::ImHints: return int(m_editor.hints);
        case Qt::ImSurroundingText: return m_editor.text;
        case Qt::ImCursorPosition: return m_editor.cursor;
        case Qt::ImAnchorPosition: return m_editor.anchor;
        case Qt::ImTextBeforeCursor: return m_editor.text.left(m_editor.cursor);
        case Qt::ImTextAfterCursor: return m_editor.text.mid(m_editor.cursor);
        case Qt::ImCurrentSelection: return m_editor.text.mid(from, to - from);
        default: return {};
    }
}

// The edit is applied to the reported text at once, so the keyboard's next
// query sees it before the app reports back.
void RemoteTextInput::edit(const QString &text, int before, int after) {
    QString &t    = m_editor.text;
    int      from = std::min(m_editor.cursor, m_editor.anchor);
    int      to   = std::max(m_editor.cursor, m_editor.anchor);
    if (from == to) {
        from = std::max(0, from - before);
        to   = std::min(int(t.size()), to + after);
    }
    t.replace(from, to - from, text);
    m_editor.cursor = m_editor.anchor = from + int(text.size());
}

// Replacements reach the service as counts around the cursor; any other
// range would need a selection protocol nobody sends.
void RemoteTextInput::commit(const QInputMethodEvent &event) {
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
    edit(text, before, after);
    emit commitString(m_editor.appId, text, before, after);
}

bool RemoteTextInput::eventFilter(QObject *watched, QEvent *event) {
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
            if (event->type() == QEvent::KeyPress) {
                if (name == QLatin1String("backspace"))
                    edit({}, 1, 0);
                emit this->key(m_editor.appId, name);
            }
            event->accept();
            return true;
        }
        default: break;
    }
    return QObject::eventFilter(watched, event);
}

RemoteTextInputService::RemoteTextInputService(RemoteTextInput *input, QObject *parent)
    : QObject(parent)
    , m_input(input) {
    m_watcher.setConnection(QDBusConnection::sessionBus());
    m_watcher.setWatchMode(QDBusServiceWatcher::WatchForUnregistration);
    connect(&m_watcher, &QDBusServiceWatcher::serviceUnregistered, this,
            [this](const QString &name) {
                if (name != m_owner)
                    return;
                m_owner.clear();
                m_watcher.setWatchedServices({});
                m_input->setService(QString());
            });
    connect(input, &RemoteTextInput::commitString, this,
            [this](const QString &appId, const QString &text, int before, int after) {
                send(QStringLiteral("CommitString"), {appId, text, before, after});
            });
    connect(input, &RemoteTextInput::key, this, [this](const QString &appId, const QString &name) {
        send(QStringLiteral("Key"), {appId, name});
    });
    connect(input, &RemoteTextInput::panelChanged, this,
            [this](const QString &appId, int covered, int height) {
                send(QStringLiteral("PanelChanged"), {appId, covered, height});
            });
}

void RemoteTextInputService::send(const QString &name, const QVariantList &arguments) {
    if (m_owner.isEmpty())
        return;
    QDBusMessage signal = QDBusMessage::createTargetedSignal(m_owner, kPath, kInterface, name);
    signal.setArguments(arguments);
    QDBusConnection::sessionBus().send(signal);
}

// The caller must be the registered service; Register itself needs the
// "text-input" permission and takes over from any earlier owner.
bool RemoteTextInputService::fromOwner() {
    if (calledFromDBus() && message().service() == m_owner)
        return true;
    sendErrorReply(QDBusError::AccessDenied, QStringLiteral("Not the registered input method"));
    return false;
}

void RemoteTextInputService::Register(const QString &appIdPrefix) {
    const qint64 pid    = callerPid(connection(), message().service());
    const auto   caller = pid >= 0 ? ServiceCaller::resolve(pid) : QString();
    if (!ServiceCaller::allowed(caller, {QStringLiteral("text-input")})) {
        sendErrorReply(QDBusError::AccessDenied, QStringLiteral("Needs the text-input permission"));
        return;
    }
    if (appIdPrefix.size() < 2 || !appIdPrefix.endsWith(QLatin1Char('.'))) {
        sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("An app id prefix ends in '.'"));
        return;
    }
    m_owner = message().service();
    m_watcher.setWatchedServices({m_owner});
    m_input->setService(appIdPrefix);
}

void RemoteTextInputService::SetEditor(const QString &appId, uint purpose, uint hints) {
    if (fromOwner() && !m_input->setEditor(appId, purpose, hints))
        sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("Not one of your apps"));
}

void RemoteTextInputService::SetSurroundingText(const QString &appId, const QString &text,
                                                int cursor, int anchor) {
    if (text.size() > 4096) {
        sendErrorReply(QDBusError::InvalidArgs, QStringLiteral("Text too long"));
        return;
    }
    if (fromOwner())
        m_input->setSurroundingText(appId, text, cursor, anchor);
}

void RemoteTextInputService::ClearEditor(const QString &appId) {
    if (fromOwner())
        m_input->clearEditor(appId);
}

void RemoteTextInputService::ShowPanel(const QString &appId) {
    if (fromOwner())
        m_input->requestPanel(appId, true);
}

void RemoteTextInputService::HidePanel(const QString &appId) {
    if (fromOwner())
        m_input->requestPanel(appId, false);
}
