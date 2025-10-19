#ifndef TELEPHONYSERVICE_H
#define TELEPHONYSERVICE_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QDBusConnection>
#include <QDBusReply>
#include <QDBusError>
#include <QTimer>

class TelephonyService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString callState READ callState NOTIFY callStateChanged)
    Q_PROPERTY(bool hasModem READ hasModem NOTIFY modemChanged)
    Q_PROPERTY(QString activeNumber READ activeNumber NOTIFY activeNumberChanged)

public:
    explicit TelephonyService(QObject *parent = nullptr);
    ~TelephonyService();

    QString callState() const;
    bool hasModem() const;
    QString activeNumber() const;

    Q_INVOKABLE void dial(const QString& number);
    Q_INVOKABLE void answer();
    Q_INVOKABLE void hangup();
    Q_INVOKABLE void sendDTMF(const QString& digit);

signals:
    void callStateChanged(const QString& state);
    void incomingCall(const QString& number);
    void callFailed(const QString& reason);
    void modemChanged(bool hasModem);
    void activeNumberChanged(const QString& number);

private slots:
    void onModemManagerPropertiesChanged(const QString& interface, const QVariantMap& changed, const QStringList& invalidated);
    void checkModemStatus();

private:
    void connectToModemManager();
    void setupDBusConnections();
    QString extractNumberFromPath(const QString& path);
    
    QDBusInterface* m_modemManager;
    QDBusInterface* m_voiceCall;
    QString m_callState;
    bool m_hasModem;
    QString m_activeNumber;
    QString m_modemPath;
    QTimer* m_reconnectTimer;
    
#ifdef Q_OS_MACOS
    // Stub mode for macOS development
    bool m_stubMode;
    void handleStubDial(const QString& number);
#endif
};

#endif // TELEPHONYSERVICE_H

