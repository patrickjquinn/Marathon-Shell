#ifndef APPMODEL_H
#define APPMODEL_H

#include <QAbstractListModel>
#include <QHash>
#include <QString>
#include <QUrl>

class App : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString icon READ icon CONSTANT)
    Q_PROPERTY(QString type READ type CONSTANT)
    Q_PROPERTY(QString exec READ exec CONSTANT)

  public:
    explicit App(const QString &id, const QString &name, const QString &icon, const QString &type,
                 const QString &exec = QString(), QObject *parent = nullptr)
        : QObject(parent)
        , m_id(id)
        , m_name(name)
        , m_icon(icon)
        , m_type(type)
        , m_exec(exec) {}

    QString id() const {
        return m_id;
    }
    QString name() const {
        return m_name;
    }
    QString icon() const {
        return m_icon;
    }
    QString type() const {
        return m_type;
    }
    QString exec() const {
        return m_exec;
    }

  private:
    QString m_id;
    QString m_name;
    QString m_icon;
    QString m_type;
    QString m_exec;
};

class AppModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

  public:
    enum AppRoles {
        IdRole = Qt::UserRole + 1,
        NameRole,
        IconRole,
        TypeRole,
        ExecRole
    };

    explicit AppModel(QObject *parent = nullptr);
    ~AppModel();

    int      rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int                    count() const {
        return m_apps.count();
    }

    Q_INVOKABLE App    *getApp(const QString &appId);
    Q_INVOKABLE App    *getAppAtIndex(int index);
    Q_INVOKABLE void    addApp(const QString &id, const QString &name, const QString &icon,
                               const QString &type, const QString &exec = QString());
    Q_INVOKABLE void    removeApp(const QString &appId);
    Q_INVOKABLE void    clear();
    Q_INVOKABLE QString getAppName(const QString &appId);
    Q_INVOKABLE QString getAppIcon(const QString &appId);
    Q_INVOKABLE bool    isNativeApp(const QString &appId);
    Q_INVOKABLE void    sortAppsByName();

    Q_INVOKABLE void    loadFromRegistry(QObject *registryObj);

  signals:
    void countChanged();

  private:
    QVector<App *>        m_apps;
    QHash<QString, App *> m_appIndex; // O(1) lookup

    void                  cleanupMissingApps(const QStringList &registryAppIds);
};

#endif // APPMODEL_H
