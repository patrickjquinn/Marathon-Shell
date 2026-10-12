#ifndef MODEMMANAGERCPP_H
#define MODEMMANAGERCPP_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QDBusInterface>
#include <QTimer>
#include <QHash>
#include <QVariantList>

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
    Q_PROPERTY(bool dataRoamingAllowed READ dataRoamingAllowed WRITE setDataRoamingAllowed NOTIFY
                   dataRoamingAllowedChanged)
    // MMModemMode bit masks (2G = 2, 3G = 4, 4G = 8, 5G = 16) the modem can be limited to.
    Q_PROPERTY(QVariantList supportedModes READ supportedModes NOTIFY modesChanged)
    Q_PROPERTY(uint allowedModes READ allowedModes NOTIFY modesChanged)
    // Emergency-call surface: emergencyOnly is true when the modem will only
    // accept emergency dials (no SIM, PIN-locked, limited service).
    // simEmergencyNumbers comes from EF_ECC and is readable while PIN-locked.
    // The lock-screen "Emergency" affordance reads both -- we never hard-code
    // the number list (3GPP TS 22.101 + the SIM provide it).
    Q_PROPERTY(bool emergencyOnly READ emergencyOnly NOTIFY emergencyOnlyChanged)
    Q_PROPERTY(
        QStringList simEmergencyNumbers READ simEmergencyNumbers NOTIFY simEmergencyNumbersChanged)

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
    bool emergencyOnly() const {
        return m_emergencyOnly;
    }
    QStringList simEmergencyNumbers() const {
        return m_simEmergencyNumbers;
    }
    bool dataRoamingAllowed() const {
        return m_dataRoamingAllowed;
    }
    QVariantList supportedModes() const {
        return m_supportedModes;
    }
    uint allowedModes() const {
        return m_allowedModes;
    }

    void             setDataRoamingAllowed(bool allowed);
    Q_INVOKABLE void setAllowedModes(uint allowed);

    Q_INVOKABLE void        enable();
    Q_INVOKABLE void        disable();
    Q_INVOKABLE void        enableData();
    Q_INVOKABLE void        disableData();

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
    void emergencyOnlyChanged();
    void simEmergencyNumbersChanged();
    void dataRoamingAllowedChanged();
    void modesChanged();

  private slots:
    void discoverModem();
    void queryModemState();
    void retryDBusConnection();
    // PropertiesChanged on any of the three modem D-Bus interfaces
    // (Modem, Modem.Signal, Modem.Modem3gpp) refreshes our cached
    // state immediately — without this we'd wait up to 60s for the
    // safety-net poll to notice e.g. a signal-bar change.
    void onModemPropertiesChanged();

  private:
    void            setupDBusConnections();
    void            attachModemPropertySubscriptions();
    void            initializeDBusConnection();
    QString         networkTypeFromAccessTech(uint accessTech);
    void            queryModes();

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

    bool            m_emergencyOnly = false;
    QStringList     m_simEmergencyNumbers;
    bool            m_dataRoamingAllowed = false;
    QVariantList    m_supportedModes;
    uint            m_allowedModes = 0;
    // Preferred mode for each allowed mask, from SupportedModes.
    QHash<uint, uint> m_preferredFor;
};

#endif
