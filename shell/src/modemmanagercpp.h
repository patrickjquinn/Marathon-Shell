#ifndef MODEMMANAGERCPP_H
#define MODEMMANAGERCPP_H

#include <QObject>
#include <QString>
#include <QDBusInterface>
#include <QTimer>

class ModemManagerCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool modemAvailable READ modemAvailable NOTIFY modemAvailableChanged)
    Q_PROPERTY(bool modemEnabled READ modemEnabled NOTIFY modemEnabledChanged)
    Q_PROPERTY(int signalStrength READ signalStrength NOTIFY signalStrengthChanged)
    Q_PROPERTY(bool registered READ registered NOTIFY registeredChanged)
    Q_PROPERTY(QString operatorName READ operatorName NOTIFY operatorNameChanged)
    Q_PROPERTY(QString networkType READ networkType NOTIFY networkTypeChanged)
    Q_PROPERTY(bool roaming READ roaming NOTIFY roamingChanged)
    Q_PROPERTY(bool simPresent READ simPresent NOTIFY simPresentChanged)
    Q_PROPERTY(bool dataEnabled READ dataEnabled NOTIFY dataEnabledChanged)
    Q_PROPERTY(bool dataConnected READ dataConnected NOTIFY dataConnectedChanged)

  public:
    explicit ModemManagerCpp(QObject *parent = nullptr);

    bool available() const {
        return m_hasModemManager;
    }
    bool modemAvailable() const {
        return m_modemAvailable;
    }
    bool modemEnabled() const {
        return m_modemEnabled;
    }
    int signalStrength() const {
        return m_signalStrength;
    }
    bool registered() const {
        return m_registered;
    }
    QString operatorName() const {
        return m_operatorName;
    }
    QString networkType() const {
        return m_networkType;
    }
    bool roaming() const {
        return m_roaming;
    }
    bool simPresent() const {
        return m_simPresent;
    }
    bool dataEnabled() const {
        return m_dataEnabled;
    }
    bool dataConnected() const {
        return m_dataConnected;
    }

    Q_INVOKABLE void enable();
    Q_INVOKABLE void disable();
    Q_INVOKABLE void enableData();
    Q_INVOKABLE void disableData();

    // APN Configuration
    Q_INVOKABLE void        setApn(const QString &apn, const QString &username = QString(),
                                   const QString &password = QString());
    Q_INVOKABLE QString     getApn() const;
    Q_INVOKABLE QVariantMap getApnSettings() const;

  signals:
    void availableChanged();
    void modemAvailableChanged();
    void modemEnabledChanged();
    void signalStrengthChanged();
    void registeredChanged();
    void operatorNameChanged();
    void networkTypeChanged();
    void roamingChanged();
    void simPresentChanged();
    void dataEnabledChanged();
    void dataConnectedChanged();

  private slots:
    void discoverModem();
    void queryModemState();
    void retryDBusConnection();

  private:
    void            setupDBusConnections();
    void            initializeDBusConnection();
    QString         networkTypeFromAccessTech(uint accessTech);

    QDBusInterface *m_mmInterface;
    QTimer         *m_stateMonitor;
    QTimer         *m_dbusRetryTimer;
    int             m_dbusRetryCount;

    bool            m_hasModemManager;
    bool            m_modemAvailable;
    bool            m_modemEnabled;
    int             m_signalStrength;
    bool            m_registered;
    QString         m_operatorName;
    QString         m_networkType;
    bool            m_roaming;
    bool            m_simPresent;
    bool            m_dataEnabled;
    bool            m_dataConnected;
    QString         m_modemPath;

    // APN settings cache
    QString m_apn;
    QString m_apnUsername;
    QString m_apnPassword;
};

#endif // MODEMMANAGERCPP_H
