#pragma once

#include <QObject>
#include <QStorageInfo>
#include <QColor>
#include <QtQmlIntegration>

class StorageInfo : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(qint64 totalSpace READ totalSpace NOTIFY changed)
    Q_PROPERTY(qint64 availableSpace READ availableSpace NOTIFY changed)
    Q_PROPERTY(qint64 usedSpace READ usedSpace NOTIFY changed)
    Q_PROPERTY(double usedPercentage READ usedPercentage NOTIFY changed)
    Q_PROPERTY(QColor usageColor READ usageColor NOTIFY changed)

    Q_PROPERTY(QString totalSpaceString READ totalSpaceString NOTIFY changed)
    Q_PROPERTY(QString availableSpaceString READ availableSpaceString NOTIFY changed)
    Q_PROPERTY(QString usedSpaceString READ usedSpaceString NOTIFY changed)

  public:
    explicit StorageInfo(QObject *parent = nullptr);

    qint64           totalSpace() const;
    qint64           availableSpace() const;
    qint64           usedSpace() const;
    double           usedPercentage() const;
    QColor           usageColor() const;

    QString          totalSpaceString() const;
    QString          availableSpaceString() const;
    QString          usedSpaceString() const;

    Q_INVOKABLE void refresh();

  signals:
    void changed();

  private:
    static QString formatBytes(qint64 bytes);

    QStorageInfo   m_storage;
};
