#ifndef TELEPHONYSERVICE_H
#define TELEPHONYSERVICE_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QDBusReply>
#include <QDBusError>
#include <QTimer>

class TelephonyService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString callState READ callState NOTIFY callStateChanged)
    Q_PROPERTY(bool hasModem READ hasModem NOTIFY modemChanged)
    Q_PROPERTY(QString activeNumber READ activeNumber NOTIFY activeNumberChanged)

  public:
    explicit TelephonyService(QObject *parent = nullptr);
    ~TelephonyService();

    QString          callState() const;
    bool             hasModem() const;
    QString          activeNumber() const;

    Q_INVOKABLE void dial(const QString &number);
    Q_INVOKABLE void answer();
    Q_INVOKABLE void hangup();
    Q_INVOKABLE void sendDTMF(const QString &digit);

    // Simulation methods for testing
    Q_INVOKABLE void simulateIncomingCall(const QString &number);
    Q_INVOKABLE void simulateCallStateChange(const QString &state);

  signals:
    void callStateChanged(const QString &state);
    void incomingCall(const QString &number);
    void callFailed(const QString &reason);
    void modemChanged(bool hasModem);
    void activeNumberChanged(const QString &number);

  private slots:
    void onModemManagerPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                         const QStringList &invalidated);
    void checkModemStatus();
    void onCallAdded(const QDBusObjectPath &callPath);

  private:
    void            connectToModemManager();
    void            setupDBusConnections();
    void            setupCallMonitoring(const QString &callPath);
    void            monitorIncomingCalls();
    QString         callStateFromModemManager(uint mmState);
    QString         extractNumberFromPath(const QString &path);

    QDBusInterface *m_modemManager;
    QDBusInterface *m_voiceCall;
    QString         m_callState;
    bool            m_hasModem;
    QString         m_activeNumber;
    QString         m_modemPath;
    QString         m_activeCallPath;
    QTimer         *m_reconnectTimer;
};

#endif // TELEPHONYSERVICE_H
