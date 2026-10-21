#pragma once

#include <QDBusContext>
#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QVariantMap>

class Apps;
class Tasks;
class Ui;
class Session;
namespace marathon {
    class Display;
}

// The shell's Keel Actions (org.shipwright.Keel.Actions on org.marathonos.shell,
// manifest shell/dbus/keel-actions.json): navigation an app cannot offer, for
// keel-mcp. Processes the shell started (its apps) may only Describe.
class ShellKeelActions : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.shipwright.Keel.Actions")

  public:
    ShellKeelActions(Apps *apps, Tasks *tasks, Ui *uiStore, Session *session,
                     marathon::Display *display, QObject *parent = nullptr);

    bool registerOnSessionBus();

  public slots:
    QString Describe();
    QString Invoke(const QString &action, const QString &arguments, const QVariantMap &options);
    QString GetEntity(const QString &type, const QString &id);
    QString FindEntities(const QString &type, const QString &query, uint limit);
    QString GetContext();

  private:
    bool                        fromApp() const;
    QString                     fail(const QString &code, const QString &message);
    QString                     run(const QString &action, const QJsonObject &args);

    Apps                       *m_apps;
    Tasks                      *m_tasks;
    Ui                         *m_uiStore;
    Session                    *m_session;
    marathon::Display                    *m_display;
    QByteArray                  m_manifest;
    QHash<QString, QJsonObject> m_tools;
};
