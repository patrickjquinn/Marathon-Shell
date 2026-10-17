#include "updatenotifier.h"

#include "../dbus/freedesktopnotifications.h"
#include "navigationroutercpp.h"

#include <QSettings>

namespace {
    // Settings' "Software updates" icon (icon-m-update).
    constexpr auto kIcon  = "arrow-circle-up";
    constexpr auto kIdKey = "updates/noticeId";
} // namespace

UpdateNotifier::UpdateNotifier(UpdateService *updates, FreedesktopNotifications *notifications,
                               NavigationRouterCpp *router, QObject *parent)
    : QObject(parent)
    , m_updates(updates)
    , m_notifications(notifications)
    , m_router(router)
    , m_id(QSettings().value(QLatin1String(kIdKey)).toUInt()) {
    connect(m_updates, &UpdateService::notice, this, &UpdateNotifier::post);
    connect(m_notifications, &FreedesktopNotifications::ActionInvoked, this,
            &UpdateNotifier::onAction);
}

void UpdateNotifier::post(UpdateService::Notice kind, const QString &version) {
    QString     summary;
    QString     body;
    QStringList actions = {QStringLiteral("default"), tr("Open")};
    switch (kind) {
        case UpdateService::Notice::Available:
            summary = tr("Update available");
            body    = tr("Marathon %1").arg(version);
            actions << QStringLiteral("download") << tr("Download") << QStringLiteral("later")
                    << tr("Later");
            break;
        case UpdateService::Notice::Restart:
            summary = tr("Restart to finish updating");
            body    = m_updates->restartScheduled() ?
                tr("Marathon %1 installs tonight while charging.").arg(version) :
                tr("Marathon %1 is ready.").arg(version);
            actions << QStringLiteral("restart") << tr("Restart now") << QStringLiteral("tonight")
                    << tr("Tonight");
            break;
        case UpdateService::Notice::RolledBack:
            summary = tr("Marathon %1 didn't start").arg(version);
            body    = tr("The update couldn't start, so Marathon went back to %1.")
                          .arg(m_updates->osVersion());
            break;
        case UpdateService::Notice::Updated:
            summary = tr("Updated to Marathon %1").arg(version);
            body    = tr("Tap to see what's new.");
            break;
    }
    m_id = m_notifications->Notify(QLatin1String(kAppName), m_id, QLatin1String(kIcon), summary,
                                   body, actions, {}, -1);
    QSettings().setValue(QLatin1String(kIdKey), m_id);
}

void UpdateNotifier::onAction(uint id, const QString &action) {
    if (id == 0 || id != m_id)
        return;
    if (action == QLatin1String("default")) {
        openSettings();
    } else if (action == QLatin1String("download")) {
        m_updates->install();
        // A gate held it back; Settings says which.
        if (m_updates->state() != UpdateService::State::Downloading)
            openSettings();
    } else if (action == QLatin1String("restart")) {
        m_updates->reboot();
    } else if (action == QLatin1String("tonight")) {
        m_updates->scheduleRestart();
    }
}

void UpdateNotifier::openSettings() {
    m_router->navigateToDeepLink(QStringLiteral("settings"), QStringLiteral("updates"));
}
