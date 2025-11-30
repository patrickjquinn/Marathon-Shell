#ifndef STORAGEMANAGER_H
#define STORAGEMANAGER_H

#include <QObject>
#include <QStorageInfo>
#include <QTimer>

class StorageManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(qint64 totalSpace READ totalSpace NOTIFY storageChanged)
    Q_PROPERTY(qint64 availableSpace READ availableSpace NOTIFY storageChanged)
    Q_PROPERTY(qint64 usedSpace READ usedSpace NOTIFY storageChanged)
    Q_PROPERTY(double usedPercentage READ usedPercentage NOTIFY storageChanged)
    Q_PROPERTY(QString totalSpaceString READ totalSpaceString NOTIFY storageChanged)
    Q_PROPERTY(QString availableSpaceString READ availableSpaceString NOTIFY storageChanged)
    Q_PROPERTY(QString usedSpaceString READ usedSpaceString NOTIFY storageChanged)

  public:
    explicit StorageManager(QObject *parent = nullptr);

    qint64 totalSpace() const {
        return m_totalSpace;
    }
    qint64 availableSpace() const {
        return m_availableSpace;
    }
    qint64 usedSpace() const {
        return m_usedSpace;
    }
    double usedPercentage() const {
        return m_usedPercentage;
    }

    QString          totalSpaceString() const;
    QString          availableSpaceString() const;
    QString          usedSpaceString() const;

    Q_INVOKABLE void refresh();

  signals:
    void storageChanged();

  private:
    void         updateStorageInfo();
    QString      formatBytes(qint64 bytes) const;

    QStorageInfo m_storageInfo;
    qint64       m_totalSpace;
    qint64       m_availableSpace;
    qint64       m_usedSpace;
    double       m_usedPercentage;
    QTimer      *m_refreshTimer;
};

#endif // STORAGEMANAGER_H
