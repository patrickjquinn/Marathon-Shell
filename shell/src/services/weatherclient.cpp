#include "weatherclient.h"

#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocale>
#include <QQmlEngine>

namespace {

    QString path() {
        return QStringLiteral("/org/marathonos/Weather");
    }

    QString iface() {
        return QStringLiteral("org.marathonos.Weather1");
    }

    QString props() {
        return QStringLiteral("org.freedesktop.DBus.Properties");
    }

} // namespace

const QString &WeatherClient::serviceName() {
    static const QString kName = QStringLiteral("org.marathonos.Weather");
    return kName;
}

WeatherClient *WeatherClient::create(QQmlEngine *engine, QJSEngine *) {
    auto *client = new WeatherClient(QDBusConnection::sessionBus(), engine);
    QQmlEngine::setObjectOwnership(client, QQmlEngine::CppOwnership);
    return client;
}

WeatherClient::WeatherClient(const QDBusConnection &bus, QObject *parent)
    : QObject(parent)
    , m_bus(bus) {
    m_bus.connect(serviceName(), path(), props(), QStringLiteral("PropertiesChanged"), this,
                  SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
}

bool WeatherClient::fahrenheit() const {
    return QLocale().measurementSystem() == QLocale::ImperialUSSystem;
}

bool WeatherClient::milesPerHour() const {
    return QLocale().measurementSystem() != QLocale::MetricSystem;
}

void WeatherClient::refresh() {
    QDBusMessage getAll =
        QDBusMessage::createMethodCall(serviceName(), path(), props(), QStringLiteral("GetAll"));
    getAll << iface();
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(getAll), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                const QDBusPendingReply<QVariantMap> reply = *call;
                if (reply.isError()) {
                    qInfo() << "[Weather] GetAll:" << reply.error().name();
                    return;
                }
                apply(reply.value());
                this->call(QStringLiteral("Refresh"));
            });
}

void WeatherClient::search(const QString &query) {
    QDBusMessage msg =
        QDBusMessage::createMethodCall(serviceName(), path(), iface(), QStringLiteral("Search"));
    msg << query;
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg, 15000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                const QDBusPendingReply<QString> reply = *call;
                if (reply.isError()) {
                    emit searchFinished({}, reply.error().message());
                    return;
                }
                emit searchFinished(
                    QJsonDocument::fromJson(reply.value().toUtf8()).array().toVariantList(), {});
            });
}

void WeatherClient::setLocation(const QVariantMap &place) {
    call(QStringLiteral("SetLocation"),
         {place.value(QStringLiteral("name")).toString(),
          place.value(QStringLiteral("region")).toString(),
          place.value(QStringLiteral("latitude")).toDouble(),
          place.value(QStringLiteral("longitude")).toDouble()});
}

void WeatherClient::setAutomatic() {
    call(QStringLiteral("SetAutomatic"));
}

void WeatherClient::onPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                        const QStringList &) {
    if (interface == iface())
        apply(changed);
}

void WeatherClient::apply(const QVariantMap &properties) {
    const auto forecast = properties.constFind(QStringLiteral("Forecast"));
    if (forecast != properties.constEnd() && forecast->toString() != m_forecastJson) {
        m_forecastJson = forecast->toString();
        m_forecast     = QJsonDocument::fromJson(m_forecastJson.toUtf8()).object().toVariantMap();
        emit forecastChanged();
    }
    const auto state = properties.constFind(QStringLiteral("State"));
    if (state != properties.constEnd() && state->toString() != m_state) {
        m_state = state->toString();
        emit stateChanged();
    }
}

void WeatherClient::call(const QString &method, const QVariantList &args) {
    QDBusMessage msg = QDBusMessage::createMethodCall(serviceName(), path(), iface(), method);
    msg.setArguments(args);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [method](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                if (call->isError())
                    qInfo() << "[Weather]" << method << call->error().name();
            });
}
