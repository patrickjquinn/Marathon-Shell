// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "keeladaptor.h"

#include "keelcall.h"
#include "keelregistry.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDebug>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace {

QString compact(const QJsonValue &value)
{
    if (value.isObject())
        return QString::fromUtf8(QJsonDocument(value.toObject()).toJson(QJsonDocument::Compact));
    if (value.isArray())
        return QString::fromUtf8(QJsonDocument(value.toArray()).toJson(QJsonDocument::Compact));
    return QStringLiteral("{}");
}

QString errorName(const QString &code)
{
    return QStringLiteral("org.shipwright.Keel.Actions.Error.") + code;
}

} // namespace

KeelActionsAdaptor::KeelActionsAdaptor(KeelActionRegistry *registry)
    : QObject(registry)
    , m_registry(registry)
{
    m_idle.setSingleShot(true);
    bool ok = false;
    const int idleMs = qEnvironmentVariableIntValue("KEEL_ACTIONS_IDLE_MS", &ok);
    m_idle.setInterval(ok && idleMs > 0 ? idleMs : DefaultIdleMs);
    connect(&m_idle, &QTimer::timeout, this, [this]() {
        if (m_inFlight > 0) {
            m_idle.start();
            return;
        }
        qInfo("Keel.Actions: idle in headless mode, quitting");
        QCoreApplication::quit();
    });
    connect(registry, &KeelActionRegistry::activity, this, &KeelActionsAdaptor::touch);
}

bool KeelActionsAdaptor::start()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning("Keel.Actions: no session bus; actions are not served");
        return false;
    }
    if (!bus.registerObject(QString::fromLatin1(Path), this, QDBusConnection::ExportAllSlots)) {
        qWarning("Keel.Actions: cannot register %s", Path);
        return false;
    }
    const QString name = m_registry->appId();
    if (!bus.registerService(name)) {
        qWarning().noquote() << "Keel.Actions: cannot own" << name << "on the session bus:" << bus.lastError().message();
        if (m_registry->headless()) {
            // Another instance serves the name; this one has nothing to do.
            QMetaObject::invokeMethod(QCoreApplication::instance(), "quit", Qt::QueuedConnection);
        }
        return false;
    }
    touch();
    return true;
}

void KeelActionsAdaptor::touch()
{
    if (m_registry->headless())
        m_idle.start();
}

void KeelActionsAdaptor::answer(KeelCall *call, const QDBusMessage &message)
{
    ++m_inFlight;
    message.setDelayedReply(true);
    const auto send = [this, call, message]() {
        --m_inFlight;
        const QDBusMessage reply = call->succeeded()
            ? message.createReply(compact(call->jsonResult()))
            : message.createErrorReply(errorName(call->errorCode()), call->errorMessage());
        QDBusConnection::sessionBus().send(reply);
        call->deleteLater();
        touch();
    };
    if (call->isFinished())
        send();
    else
        connect(call, &KeelCall::completed, this, send);
}

QString KeelActionsAdaptor::Describe()
{
    touch();
    return compact(m_registry->effectiveManifest());
}

QString KeelActionsAdaptor::Invoke(const QString &action, const QString &arguments, const QVariantMap &options,
                                   const QDBusMessage &message)
{
    QJsonParseError error{};
    const QJsonDocument doc = QJsonDocument::fromJson(arguments.toUtf8(), &error);
    if (!doc.isObject()) {
        message.setDelayedReply(true);
        QDBusConnection::sessionBus().send(message.createErrorReply(
            errorName(KeelCall::InvalidArguments), QStringLiteral("arguments must be a JSON object")));
        return {};
    }
    answer(m_registry->invoke(action, doc.object().toVariantMap(), options), message);
    return {};
}

QString KeelActionsAdaptor::GetEntity(const QString &type, const QString &id, const QDBusMessage &message)
{
    answer(m_registry->getEntity(type, id), message);
    return {};
}

QString KeelActionsAdaptor::FindEntities(const QString &type, const QString &query, uint limit,
                                         const QDBusMessage &message)
{
    answer(m_registry->findEntities(type, query, static_cast<int>(qMin<uint>(limit, 1000))), message);
    return {};
}

QString KeelActionsAdaptor::GetContext()
{
    touch();
    return compact(m_registry->context());
}
