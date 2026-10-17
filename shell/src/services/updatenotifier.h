#ifndef UPDATENOTIFIER_H
#define UPDATENOTIFIER_H

#include "updateservice.h"

#include <QObject>

class FreedesktopNotifications;
class NavigationRouterCpp;

// UpdateService's news as notifications from "Software update", the way
// Android's system update channel shows them: one at a time, each replacing
// the last, and a tap opens Settings → Software updates.
class UpdateNotifier : public QObject {
    Q_OBJECT

  public:
    static constexpr auto kAppName = "Software update";

    UpdateNotifier(UpdateService *updates, FreedesktopNotifications *notifications,
                   NavigationRouterCpp *router, QObject *parent = nullptr);

  private:
    void                      post(UpdateService::Notice kind, const QString &version);
    void                      onAction(uint id, const QString &action);
    void                      openSettings();

    UpdateService            *m_updates;
    FreedesktopNotifications *m_notifications;
    NavigationRouterCpp      *m_router;
    uint                      m_id;
};

#endif
