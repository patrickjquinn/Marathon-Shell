#ifndef TELEPHONYSERVICE_H
#define TELEPHONYSERVICE_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QDBusReply>
#include <QDBusError>
#include <QDBusUnixFileDescriptor>
#include <QTimer>

class TelephonyService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString callState READ callState NOTIFY callStateChanged)
    Q_PROPERTY(bool hasModem READ hasModem NOTIFY modemChanged)
    Q_PROPERTY(QString activeNumber READ activeNumber NOTIFY activeNumberChanged)

  public:
    explicit TelephonyService(QObject *parent = nullptr);
    ~TelephonyService() override;

    QString          callState() const;
    bool             hasModem() const;
    QString          activeNumber() const;

    Q_INVOKABLE void dial(const QString &number);
    // Dials with the explicit understanding that this is an emergency call.
    // The radio still decides whether the number is treated as emergency
    // (3GPP TS 22.101 + SIM EF_ECC); we just log the attempt for audit.
    Q_INVOKABLE void dialEmergency(const QString &number);
    Q_INVOKABLE void answer();
    Q_INVOKABLE void hangup();
    Q_INVOKABLE void sendDTMF(const QString &digit);

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
    void onCallDeleted(const QDBusObjectPath &callPath);

  private:
    void    connectToModemManager();
    void    setupDBusConnections();
    void    setupCallMonitoring(const QString &callPath);
    void    monitorIncomingCalls();
    QString callStateFromModemManager(uint mmState);
    QString extractNumberFromPath(const QString &path);

    // Per-call sleep block inhibitor -- held while a call is in progress so
    // the system cannot suspend mid-call. Pattern lifted from Plasma-Dialer
    // (modem-daemon/src/call-manager.cpp) and GNOME Calls.
    void                    acquireCallInhibit();
    void                    releaseCallInhibit();

    QDBusInterface         *m_modemManager;
    QDBusInterface         *m_voiceCall;
    QString                 m_callState;
    bool                    m_hasModem;
    QString                 m_activeNumber;
    QString                 m_modemPath;
    QString                 m_activeCallPath;
    QTimer                 *m_reconnectTimer;
    QDBusUnixFileDescriptor m_callInhibitFd;
};

#endif
