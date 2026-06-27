#pragma once

#include <QDBusObjectPath>
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class QDBusInterface;

// Cell Broadcast (SMS-CB / ETWS / CMAS) emergency alerts via the
// org.freedesktop.ModemManager1.Modem.CellBroadcast interface introduced
// in ModemManager 1.22 and stabilised in 1.24. Cell broadcasts are
// network-pushed messages targeted at a geographic area (typically a
// cell or set of cells) without requiring an internet connection or any
// app subscription — the cellular network operator and government
// agencies use them for:
//
//   • Amber Alerts (US WEA — channels 4370-4399, severity escalating)
//   • Severe weather (CMAS Imminent Threat, WEA channel 4371)
//   • Civil emergencies (Presidential, channel 4370 — non-dismissable)
//   • ETWS earthquake / tsunami (Japan, EU)
//   • Public Safety (cellular network advisories)
//
// Marathon surfaces incoming broadcasts via a full-screen overlay
// (MarathonCellBroadcastOverlay.qml) that respects WEA dismissal rules:
// Class 0 (Presidential) cannot be dismissed; Class 1-3 require an
// explicit acknowledge tap. Vibration + tone follow the WEA
// distinguishable alert profile.
//
// On platforms without MM 1.22+ (older pmOS images, Sailfish) or
// without a 3GPP modem, the manager stays dormant — no broadcasts are
// reported and the QML overlay is never shown.
class CellBroadcastManager : public QObject {
    Q_OBJECT
    // QML_ELEMENT / QML_SINGLETON are registered in main.cpp; not declared
    // here so the header stays free of QtQml deps for future split.
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QVariantList activeBroadcasts READ activeBroadcasts NOTIFY activeBroadcastsChanged)

  public:
    explicit CellBroadcastManager(QObject *parent = nullptr);
    ~CellBroadcastManager() override;

    bool available() const {
        return m_available;
    }
    QVariantList activeBroadcasts() const {
        return m_activeBroadcasts;
    }

    // Mark a broadcast as acknowledged by the user. Removes it from
    // `activeBroadcasts`. Class 0 (Presidential WEA) is silently kept
    // active per FCC §10.500 — the platform must show it until the user
    // tap-acks specifically that severity tier.
    Q_INVOKABLE void acknowledge(const QString &broadcastPath);

  signals:
    void availableChanged();
    void activeBroadcastsChanged();
    // Emitted exactly once per incoming broadcast, before
    // activeBroadcastsChanged. QML hooks haptics / tone here.
    void broadcastReceived(const QVariantMap &broadcast);

  private slots:
    void onModemAdded(const QDBusObjectPath &path, const QVariantMap &interfaces);
    void onModemRemoved(const QDBusObjectPath &path, const QStringList &interfaces);
    void onCellBroadcastAdded(const QDBusObjectPath &path, bool received);
    void onCellBroadcastDeleted(const QDBusObjectPath &path);

  private:
    void enumerateModems();
    void attachToModem(const QString &modemPath);
    void detachFromModem(const QString &modemPath);
    void loadBroadcast(const QString &broadcastPath);
    // Classify a broadcast by its 3GPP Channel ID. Returns one of:
    //   "presidential", "imminent", "amber", "ETWS", "test", "other"
    static QString  classifyChannel(uint channelId);
    static bool     isNonDismissable(const QString &category);

    QString         m_modemPath; // active 3GPP modem, if any
    QDBusInterface *m_cbInterface = nullptr;
    bool            m_available   = false;
    QVariantList    m_activeBroadcasts;
};
