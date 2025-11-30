#ifndef BLUETOOTHAGENT_H
#define BLUETOOTHAGENT_H

#include <QObject>
#include <QString>
#include <QDBusContext>
#include <QDBusObjectPath>
#include <QDBusMessage>

/**
 * BluetoothAgent - Implements org.bluez.Agent1 interface
 * 
 * Handles Bluetooth pairing requests including:
 * - PIN code requests
 * - Passkey requests
 * - Passkey display
 * - Confirmation requests
 * - Authorization requests
 */
class BluetoothAgent : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bluez.Agent1")

  public:
    explicit BluetoothAgent(QObject *parent = nullptr);
    ~BluetoothAgent() override;

    bool registerAgent();
    void unregisterAgent();

  public slots:
    // org.bluez.Agent1 interface methods
    void    Release();
    QString RequestPinCode(const QDBusObjectPath &device);
    quint32 RequestPasskey(const QDBusObjectPath &device);
    void    DisplayPinCode(const QDBusObjectPath &device, const QString &pincode);
    void    DisplayPasskey(const QDBusObjectPath &device, quint32 passkey, quint16 entered);
    void    RequestConfirmation(const QDBusObjectPath &device, quint32 passkey);
    void    RequestAuthorization(const QDBusObjectPath &device);
    void    AuthorizeService(const QDBusObjectPath &device, const QString &uuid);
    void    Cancel();

  signals:
    // Signals to UI for user interaction
    void pairingPinCodeRequested(const QString &devicePath, const QString &deviceName);
    void pairingPasskeyRequested(const QString &devicePath, const QString &deviceName);
    void pairingPasskeyDisplay(const QString &devicePath, const QString &deviceName,
                               quint32 passkey);
    void pairingConfirmationRequested(const QString &devicePath, const QString &deviceName,
                                      quint32 passkey);
    void pairingAuthorizationRequested(const QString &devicePath, const QString &deviceName);
    void pairingCancelled();
    void pairingCompleted(const QString &devicePath, bool success);

  public:
    // Methods for UI to respond to pairing requests
    void providePinCode(const QString &pinCode);
    void providePasskey(quint32 passkey);
    void confirmPairing(bool confirmed);
    void authorizeConnection(bool authorized);

  private:
    QString getDeviceName(const QString &devicePath);
    void    sendDBusError(const QString &errorName, const QString &errorMessage);

    QString m_agentPath;
    QString m_pendingDevicePath;
    bool    m_registered;

    // For synchronous D-Bus method responses
    QDBusMessage m_pendingMessage;
    bool         m_waitingForResponse;
};

#endif // BLUETOOTHAGENT_H
