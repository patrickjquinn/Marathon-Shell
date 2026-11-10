// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's Sailfish Policy API for Qt 6: PolicyValue, one device policy's
// value. The API of Sailfish's libsailfishpolicy 0.4.26 (public header and
// documentation); Keel's implementation reads the policies and never writes
// them: setValue(), setKeyValue() and enforcePolicy() are for MDM
// applications and return false here.
//
// value() is true or false while the policy store can be read (a policy no
// MDM has set is true, as on a device without MDM), and an invalid QVariant
// when it cannot (see accesspolicy.h): never true by default.

#ifndef SAILFISH_POLICYVALUE_H
#define SAILFISH_POLICYVALUE_H

#include <QObject>
#include <QString>
#include <QVariant>
#include <policytypes.h>

namespace Sailfish {

class PolicyValuePrivate;

class Q_DECL_EXPORT PolicyValue : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int policyType READ policyType WRITE setPolicyType NOTIFY policyTypeChanged)
    Q_PROPERTY(QString key READ key WRITE setKey NOTIFY keyChanged)
    Q_PROPERTY(QVariant value READ value NOTIFY valueChanged)

public:
    enum PolicyType {
        Unknown = PolicyTypes::Unknown,
        CameraEnabled = PolicyTypes::CameraEnabled,
        LocationSettingsEnabled = PolicyTypes::LocationSettingsEnabled,
        OsUpdatesEnabled = PolicyTypes::OsUpdatesEnabled,
        SideLoadingSettingsEnabled = PolicyTypes::SideLoadingSettingsEnabled,
        DeveloperModeSettingsEnabled = PolicyTypes::DeveloperModeSettingsEnabled,
        ApplicationInstallationEnabled = PolicyTypes::ApplicationInstallationEnabled,
        WlanToggleEnabled = PolicyTypes::WlanToggleEnabled,
        BluetoothToggleEnabled = PolicyTypes::BluetoothToggleEnabled,
        InternetSharingEnabled = PolicyTypes::InternetSharingEnabled,
        DeviceResetEnabled = PolicyTypes::DeviceResetEnabled,
        ScreenshotEnabled = PolicyTypes::ScreenshotEnabled,
        MobileNetworkSettingsEnabled = PolicyTypes::MobileNetworkSettingsEnabled,
        UsbMassStorageEnabled = PolicyTypes::UsbMassStorageEnabled,
        UsbDeveloperModeEnabled = PolicyTypes::UsbDeveloperModeEnabled,
        UsbMtpEnabled = PolicyTypes::UsbMtpEnabled,
        UsbHostEnabled = PolicyTypes::UsbHostEnabled,
        UsbConnectionSharingEnabled = PolicyTypes::UsbConnectionSharingEnabled,
        UsbDiagnosticModeEnabled = PolicyTypes::UsbDiagnosticModeEnabled,
        UsbAdbEnabled = PolicyTypes::UsbAdbEnabled,
        DateTimeSettingsEnabled = PolicyTypes::DateTimeSettingsEnabled,
        MicrophoneEnabled = PolicyTypes::MicrophoneEnabled,
        FlightModeToggleEnabled = PolicyTypes::FlightModeToggleEnabled,
        NetworkProxySettingsEnabled = PolicyTypes::NetworkProxySettingsEnabled,
        NetworkDataCounterSettingsEnabled = PolicyTypes::NetworkDataCounterSettingsEnabled,
        CallStatisticsSettingsEnabled = PolicyTypes::CallStatisticsSettingsEnabled,
        CellularTechnologySettingsEnabled = PolicyTypes::CellularTechnologySettingsEnabled,
        MobileDataAccessPointSettingsEnabled = PolicyTypes::MobileDataAccessPointSettingsEnabled,
        VpnConnectionSettingsEnabled = PolicyTypes::VpnConnectionSettingsEnabled,
        VpnConfigurationSettingsEnabled = PolicyTypes::VpnConfigurationSettingsEnabled,
        BrowserEnabled = PolicyTypes::BrowserEnabled,
        AccountCreationEnabled = PolicyTypes::AccountCreationEnabled,
        CameraAppEnabled = PolicyTypes::CameraAppEnabled,
        RingtoneLevelEnabled = PolicyTypes::RingtoneLevelEnabled,
        AppsupportEnabled = PolicyTypes::AppsupportEnabled,
    };
    Q_ENUM(PolicyType)

    explicit PolicyValue(QObject *parent = nullptr);
    ~PolicyValue() override;

    // The type and its key name ("CameraEnabled" for CameraEnabled) set
    // each other.
    int policyType() const;
    void setPolicyType(int type);
    QString key() const;
    void setKey(const QString &newKey);

    QVariant value() const;

    // For MDM applications.
    static QVariant keyValue(const QString &key);
    static QVariant keyValue(int type);
    static bool setKeyValue(const QString &key, const QVariant &value);
    static bool setKeyValue(int type, const QVariant &value);
    bool setValue(const QVariant &value);
    static bool enforcePolicy(int type, bool value);
    static bool enforcePolicy(const QString &key, bool value);

Q_SIGNALS:
    void policyTypeChanged();
    void keyChanged();
    void valueChanged();

private:
    void update();

    PolicyValuePrivate *d;
    Q_DISABLE_COPY(PolicyValue)
};

} // namespace Sailfish

#endif // SAILFISH_POLICYVALUE_H
