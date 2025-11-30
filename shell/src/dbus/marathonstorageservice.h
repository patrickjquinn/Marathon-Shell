#ifndef MARATHONSTORAGESERVICE_H
#define MARATHONSTORAGESERVICE_H

#include <QObject>
#include <QDBusContext>
#include <QDBusConnection>
#include <QVariantMap>

class StorageManager;

class MarathonStorageService : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathon.StorageService")

    Q_PROPERTY(qint64 TotalSpace READ totalSpace NOTIFY StorageChanged)
    Q_PROPERTY(qint64 UsedSpace READ usedSpace NOTIFY StorageChanged)
    Q_PROPERTY(qint64 AvailableSpace READ availableSpace NOTIFY StorageChanged)
    Q_PROPERTY(double UsedPercentage READ usedPercentage NOTIFY StorageChanged)

  public:
    explicit MarathonStorageService(StorageManager *storageManager, QObject *parent = nullptr);
    ~MarathonStorageService();

    bool   registerService();

    qint64 totalSpace() const;
    qint64 usedSpace() const;
    qint64 availableSpace() const;
    double usedPercentage() const;

  public slots:
    QVariantMap GetStorageInfo();
    QString     FormatSize(qint64 bytes);
    bool        RequestStoragePermission(const QString &appId, const QString &path);

  signals:
    void StorageChanged();

  private:
    StorageManager *m_storageManager;
};

#endif // MARATHONSTORAGESERVICE_H
