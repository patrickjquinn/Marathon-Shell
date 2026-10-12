#pragma once

#include <QDBusConnection>
#include <QObject>
#include <QVariantMap>

// The shell's published Keel ambience (org.marathonos.Shell.Ambience1), for
// relaying to the app through KeelHost.
class AmbienceClient : public QObject {
    Q_OBJECT

  public:
    explicit AmbienceClient(const QDBusConnection &bus = QDBusConnection::sessionBus(),
                            QObject               *parent = nullptr);

    QVariantMap ambience() const {
        return m_ambience;
    }

    // Blocking fetch, for the moment before the app's Keel starts: Keel reads
    // the ambience from its environment then, and a pool spare's main thread
    // is too busy during warm-up to answer Keel's own GetAll in time.
    bool fetchNow(int timeoutMs);

  signals:
    void ambienceChanged(const QVariantMap &ambience);

  private slots:
    void onAmbienceChanged(const QVariantMap &ambience);

  private:
    void fetch();

    QDBusConnection m_bus;
    QVariantMap     m_ambience;
};
