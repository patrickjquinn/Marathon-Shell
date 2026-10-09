// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's Sailfish Policy API for Qt 6: AccessPolicy, every device policy as
// a property (Sailfish.Policy's AccessPolicy singleton in QML). The API of
// Sailfish's libsailfishpolicy 0.4.26 (public header and documentation).
//
// Where the values come from, as on Sailfish OS: the key file
// /var/lib/policy/policy.conf (group [policy], one boolean per policy type
// name, e.g. CameraEnabled=false), which MDM applications write, and the
// privacy switch daemon (org.sailfishos.privacyswitch on the session bus)
// for privacyModeActive. Read only and fail-closed: a property is true only
// when the store was read and no MDM disabled the policy. It is false when
// the policy is disabled or its value is not a boolean, and for every policy
// while the store cannot be read: /var/lib/policy missing or unreadable,
// policy.conf unreadable or not a key file, or Sailfish's (Qt 5) access
// policy plugin installed, whose values Keel cannot read.
// The setters are for MDM applications; they return false here.

#ifndef SAILFISH_ACCESSPOLICY_H
#define SAILFISH_ACCESSPOLICY_H

#include <QObject>

namespace Sailfish {

class AccessPolicyPrivate;

class Q_DECL_EXPORT AccessPolicy : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool cameraEnabled READ cameraEnabled NOTIFY cameraEnabledChanged)
    Q_PROPERTY(bool cameraAppEnabled READ cameraAppEnabled NOTIFY cameraAppEnabledChanged)
    Q_PROPERTY(bool locationSettingsEnabled READ locationSettingsEnabled NOTIFY locationSettingsEnabledChanged)
    Q_PROPERTY(bool osUpdatesEnabled READ osUpdatesEnabled NOTIFY osUpdatesEnabledChanged)
    Q_PROPERTY(bool flightModeToggleEnabled READ flightModeToggleEnabled NOTIFY flightModeToggleEnabledChanged)
    Q_PROPERTY(bool wlanToggleEnabled READ wlanToggleEnabled NOTIFY wlanToggleEnabledChanged)
    Q_PROPERTY(bool bluetoothToggleEnabled READ bluetoothToggleEnabled NOTIFY bluetoothToggleEnabledChanged)
    Q_PROPERTY(bool internetSharingEnabled READ internetSharingEnabled NOTIFY internetSharingEnabledChanged)
    Q_PROPERTY(bool sideLoadingSettingsEnabled READ sideLoadingSettingsEnabled NOTIFY sideLoadingSettingsEnabledChanged)
    Q_PROPERTY(bool developerModeSettingsEnabled READ developerModeSettingsEnabled NOTIFY developerModeSettingsEnabledChanged)
    Q_PROPERTY(bool applicationInstallationEnabled READ applicationInstallationEnabled NOTIFY applicationInstallationEnabledChanged)
    Q_PROPERTY(bool dateTimeSettingsEnabled READ dateTimeSettingsEnabled NOTIFY dateTimeSettingsEnabledChanged)
    Q_PROPERTY(bool deviceResetEnabled READ deviceResetEnabled NOTIFY deviceResetEnabledChanged)
    Q_PROPERTY(bool screenshotEnabled READ screenshotEnabled NOTIFY screenshotEnabledChanged)
    Q_PROPERTY(bool microphoneEnabled READ microphoneEnabled NOTIFY microphoneEnabledChanged)
    Q_PROPERTY(bool mobileNetworkSettingsEnabled READ mobileNetworkSettingsEnabled NOTIFY mobileNetworkSettingsEnabledChanged)
    Q_PROPERTY(bool networkProxySettingsEnabled READ networkProxySettingsEnabled NOTIFY networkProxySettingsEnabledChanged)
    Q_PROPERTY(bool networkDataCounterSettingsEnabled READ networkDataCounterSettingsEnabled NOTIFY networkDataCounterSettingsEnabledChanged)
    Q_PROPERTY(bool callStatisticsSettingsEnabled READ callStatisticsSettingsEnabled NOTIFY callStatisticsSettingsEnabledChanged)
    Q_PROPERTY(bool cellularTechnologySettingsEnabled READ cellularTechnologySettingsEnabled NOTIFY cellularTechnologySettingsEnabledChanged)
    Q_PROPERTY(bool mobileDataAccessPointSettingsEnabled READ mobileDataAccessPointSettingsEnabled NOTIFY mobileDataAccessPointSettingsEnabledChanged)
    Q_PROPERTY(bool vpnConnectionSettingsEnabled READ vpnConnectionSettingsEnabled NOTIFY vpnConnectionSettingsEnabledChanged)
    Q_PROPERTY(bool vpnConfigurationSettingsEnabled READ vpnConfigurationSettingsEnabled NOTIFY vpnConfigurationSettingsEnabledChanged)
    Q_PROPERTY(bool browserEnabled READ browserEnabled NOTIFY browserEnabledChanged)
    Q_PROPERTY(bool accountCreationEnabled READ accountCreationEnabled NOTIFY accountCreationEnabledChanged)
    Q_PROPERTY(bool ringtoneLevelEnabled READ ringtoneLevelEnabled NOTIFY ringtoneLevelEnabledChanged)
    Q_PROPERTY(bool appsupportEnabled READ appsupportEnabled NOTIFY appsupportEnabledChanged)
    Q_PROPERTY(bool privacyModeActive READ privacyModeActive NOTIFY privacyModeActiveChanged)

public:
    explicit AccessPolicy(QObject *parent = nullptr);
    ~AccessPolicy() override;

    bool cameraEnabled() const;
    bool setCameraEnabled(bool enabled);
    bool cameraAppEnabled() const;
    bool setCameraAppEnabled(bool enabled);
    bool locationSettingsEnabled() const;
    bool setLocationSettingsEnabled(bool enabled);
    bool osUpdatesEnabled() const;
    bool setOsUpdatesEnabled(bool enabled);
    bool flightModeToggleEnabled() const;
    bool setFlightModeToggleEnabled(bool enabled);
    bool wlanToggleEnabled() const;
    bool setWlanToggleEnabled(bool enabled);
    bool bluetoothToggleEnabled() const;
    bool setBluetoothToggleEnabled(bool enabled);
    bool internetSharingEnabled() const;
    bool setInternetSharingEnabled(bool enabled);
    bool sideLoadingSettingsEnabled() const;
    bool setSideLoadingSettingsEnabled(bool enabled);
    bool developerModeSettingsEnabled() const;
    bool setDeveloperModeSettingsEnabled(bool enabled);
    bool applicationInstallationEnabled() const;
    bool setApplicationInstallationEnabled(bool enabled);
    bool dateTimeSettingsEnabled() const;
    bool setDateTimeSettingsEnabled(bool enabled);
    bool deviceResetEnabled() const;
    bool setDeviceResetEnabled(bool enabled);
    bool screenshotEnabled() const;
    bool setScreenshotEnabled(bool enabled);
    bool microphoneEnabled() const;
    bool setMicrophoneEnabled(bool enabled);
    bool mobileNetworkSettingsEnabled() const;
    bool setMobileNetworkSettingsEnabled(bool enabled);
    bool networkProxySettingsEnabled() const;
    bool setNetworkProxySettingsEnabled(bool enabled);
    bool networkDataCounterSettingsEnabled() const;
    bool setNetworkDataCounterSettingsEnabled(bool enabled);
    bool callStatisticsSettingsEnabled() const;
    bool setCallStatisticsSettingsEnabled(bool enabled);
    bool cellularTechnologySettingsEnabled() const;
    bool setCellularTechnologySettingsEnabled(bool enabled);
    bool mobileDataAccessPointSettingsEnabled() const;
    bool setMobileDataAccessPointSettingsEnabled(bool enabled);
    bool vpnConnectionSettingsEnabled() const;
    bool setVpnConnectionSettingsEnabled(bool enabled);
    bool vpnConfigurationSettingsEnabled() const;
    bool setVpnConfigurationSettingsEnabled(bool enabled);
    bool browserEnabled() const;
    bool setBrowserEnabled(bool enabled);
    bool accountCreationEnabled() const;
    bool setAccountCreationEnabled(bool enabled);
    bool ringtoneLevelEnabled() const;
    bool setRingtoneLevelEnabled(bool enabled);
    bool appsupportEnabled() const;
    bool setAppsupportEnabled(bool enabled);

    bool privacyModeActive() const;

Q_SIGNALS:
    void cameraEnabledChanged();
    void cameraAppEnabledChanged();
    void locationSettingsEnabledChanged();
    void osUpdatesEnabledChanged();
    void flightModeToggleEnabledChanged();
    void wlanToggleEnabledChanged();
    void bluetoothToggleEnabledChanged();
    void internetSharingEnabledChanged();
    void sideLoadingSettingsEnabledChanged();
    void developerModeSettingsEnabledChanged();
    void applicationInstallationEnabledChanged();
    void dateTimeSettingsEnabledChanged();
    void deviceResetEnabledChanged();
    void screenshotEnabledChanged();
    void microphoneEnabledChanged();
    void mobileNetworkSettingsEnabledChanged();
    void networkProxySettingsEnabledChanged();
    void networkDataCounterSettingsEnabledChanged();
    void callStatisticsSettingsEnabledChanged();
    void cellularTechnologySettingsEnabledChanged();
    void mobileDataAccessPointSettingsEnabledChanged();
    void vpnConnectionSettingsEnabledChanged();
    void vpnConfigurationSettingsEnabledChanged();
    void browserEnabledChanged();
    void accountCreationEnabledChanged();
    void ringtoneLevelEnabledChanged();
    void appsupportEnabledChanged();
    void privacyModeActiveChanged();

private:
    void update();

    AccessPolicyPrivate *d;
    Q_DISABLE_COPY(AccessPolicy)
};

} // namespace Sailfish

#endif // SAILFISH_ACCESSPOLICY_H
