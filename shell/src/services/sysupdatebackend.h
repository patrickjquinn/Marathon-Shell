#ifndef SYSUPDATEBACKEND_H
#define SYSUPDATEBACKEND_H

#include "updateservice.h"

#include <QDBusObjectPath>
#include <QVariantMap>

class QNetworkAccessManager;

// UpdateBackend over systemd-sysupdated's org.freedesktop.sysupdate1 (system
// bus, polkit: check/update are allowed for the active session). Release
// size and notes come from the target's AppStream catalog, which the
// publisher writes next to the signed SHA256SUMS.
class SysupdateBackend : public UpdateBackend {
    Q_OBJECT

  public:
    explicit SysupdateBackend(QObject *parent = nullptr);

    void probe() override;
    void checkNew() override;
    void fetchReleaseInfo(const QString &version) override;
    void install() override;
    void cancel() override;

    struct Release {
        qint64  downloadSize = -1;
        QString notes;
    };
    static Release          parseAppStream(const QByteArray &xml, const QString &version);
    static UpdateConditions systemConditions();

  private slots:
    void onJobRemoved(qulonglong id, const QDBusObjectPath &path, int status);
    void onJobPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                const QStringList &invalidated);

  private:
    QNetworkAccessManager *m_net;
    QString                m_target;
    QString                m_jobPath;
    qulonglong             m_jobId = 0;
    QString                m_installingVersion;
};

#endif
