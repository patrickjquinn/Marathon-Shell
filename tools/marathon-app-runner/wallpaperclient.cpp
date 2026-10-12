#include "wallpaperclient.h"

#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QMetaProperty>

WallpaperClient::WallpaperClient(QObject *settings, const QDBusConnection &bus, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
    , m_bus(bus) {
    const QMetaObject *mo   = m_settings->metaObject();
    const QMetaProperty prop = mo->property(mo->indexOfProperty("wallpaperPath"));
    connect(m_settings, prop.notifySignal(), this,
            metaObject()->method(metaObject()->indexOfSignal("currentWallpaperChanged()")));

    const QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.marathonos.Shell"), QStringLiteral("/org/marathonos/Shell/Wallpaper"),
        QStringLiteral("org.marathonos.Shell.Wallpaper1"), QStringLiteral("GetWallpapers"));
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        const QDBusPendingReply<QVariantList> reply = *w;
        if (reply.isValid()) {
            m_wallpapers.clear();
            for (const QVariant &v : reply.value())
                m_wallpapers << qdbus_cast<QVariantMap>(v);
            emit wallpapersChanged();
        }
        w->deleteLater();
    });
}

QString WallpaperClient::currentWallpaper() const {
    return m_settings->property("wallpaperPath").toString();
}

void WallpaperClient::setWallpaper(const QString &path, bool) {
    m_settings->setProperty("wallpaperPath", path);
}
