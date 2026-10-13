// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "coveractions.h"

#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusMessage>
#include <QDBusReply>
#include <QLoggingCategory>

Q_DECLARE_LOGGING_CATEGORY(lcKeelShell)

namespace keel {

static const char *const kLipstick = "com.jolla.lipstick";

CoverActions::CoverActions(const QDBusConnection &bus, const QString &service, QObject *parent)
    : QObject(parent)
    , m_bus(bus)
    , m_service(service)
    , m_path(objectPath(service))
{
    if (!m_bus.isConnected()) {
        qCWarning(lcKeelShell) << "cover actions: no session bus";
        return;
    }
    if (!m_bus.registerObject(m_path, this, QDBusConnection::ExportScriptableSlots)) {
        qCWarning(lcKeelShell) << "cover actions: cannot serve" << m_path << m_bus.lastError().message();
        return;
    }
    if (!m_bus.registerService(m_service)) {
        qCWarning(lcKeelShell) << "cover actions: cannot own" << m_service << m_bus.lastError().message();
        m_bus.unregisterObject(m_path);
        return;
    }
    m_registered = true;
}

CoverActions::~CoverActions()
{
    if (m_registered) {
        m_bus.unregisterService(m_service);
        m_bus.unregisterObject(m_path);
    }
}

// A D-Bus name element: [A-Za-z0-9_], not starting with a digit, not empty.
static QString nameElement(const QString &text)
{
    QString out;
    out.reserve(text.size());
    for (const QChar c : text) {
        const ushort u = c.unicode();
        const bool ok = (u >= 'a' && u <= 'z') || (u >= 'A' && u <= 'Z') || (u >= '0' && u <= '9') || u == '_';
        out.append(ok ? c : QLatin1Char('_'));
    }
    if (out.isEmpty() || out.front().isDigit())
        out.prepend(QLatin1Char('_'));
    return out;
}

QString CoverActions::serviceName(const QString &organization, const QString &application,
                                  qint64 pid, uint windowId)
{
    QStringList parts{QStringLiteral("org"), QStringLiteral("sailfishos"), QStringLiteral("coveraction")};
    const QStringList org = organization.split(QLatin1Char('.'), Qt::SkipEmptyParts);
    for (const QString &p : org)
        parts << nameElement(p);
    parts << nameElement(application.isEmpty() ? QStringLiteral("app") : application);
    parts << QStringLiteral("pid%1").arg(pid) << QStringLiteral("id%1").arg(windowId);
    return parts.join(QLatin1Char('.'));
}

QString CoverActions::objectPath(const QString &service)
{
    return QLatin1Char('/') + QString(service).replace(QLatin1Char('.'), QLatin1Char('/'));
}

QString CoverActions::propertyValue(const QString &service, const QStringList &icons, bool iconBackground)
{
    if (icons.isEmpty())
        return QString();
    QStringList fields;
    for (int i = 0; i < icons.size(); ++i)
        fields << service << QStringLiteral("trigger") << QString::number(i) << icons.at(i);
    fields << QLatin1String(iconBackground ? "1" : "0");
    return fields.join(QLatin1Char('\n'));
}

void CoverActions::trigger(int index)
{
    // Only Lipstick taps covers.
    const QString sender = calledFromDBus() ? message().service() : QString();
    const QDBusReply<QString> owner = m_bus.interface()->serviceOwner(QString::fromLatin1(kLipstick));
    if (sender.isEmpty() || !owner.isValid() || owner.value() != sender) {
        qCWarning(lcKeelShell) << "cover actions: trigger from" << sender << "refused (not" << kLipstick << ")";
        if (calledFromDBus())
            sendErrorReply(QDBusError::AccessDenied, QStringLiteral("only Lipstick triggers cover actions"));
        return;
    }
    emit triggered(index);
}

} // namespace keel
