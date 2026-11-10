// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// See accesspolicy.h.

#include "accesspolicy.h"

#include "policystore_p.h"
#include "policyvalue.h"

#include <QLoggingCategory>

#include <array>

namespace Sailfish {

namespace {

struct Entry
{
    PolicyValue::PolicyType type;
    void (AccessPolicy::*changed)();
};

// The properties, in declaration order.
const std::array<Entry, 27> Entries = { {
    { PolicyValue::CameraEnabled, &AccessPolicy::cameraEnabledChanged },
    { PolicyValue::CameraAppEnabled, &AccessPolicy::cameraAppEnabledChanged },
    { PolicyValue::LocationSettingsEnabled, &AccessPolicy::locationSettingsEnabledChanged },
    { PolicyValue::OsUpdatesEnabled, &AccessPolicy::osUpdatesEnabledChanged },
    { PolicyValue::FlightModeToggleEnabled, &AccessPolicy::flightModeToggleEnabledChanged },
    { PolicyValue::WlanToggleEnabled, &AccessPolicy::wlanToggleEnabledChanged },
    { PolicyValue::BluetoothToggleEnabled, &AccessPolicy::bluetoothToggleEnabledChanged },
    { PolicyValue::InternetSharingEnabled, &AccessPolicy::internetSharingEnabledChanged },
    { PolicyValue::SideLoadingSettingsEnabled, &AccessPolicy::sideLoadingSettingsEnabledChanged },
    { PolicyValue::DeveloperModeSettingsEnabled, &AccessPolicy::developerModeSettingsEnabledChanged },
    { PolicyValue::ApplicationInstallationEnabled, &AccessPolicy::applicationInstallationEnabledChanged },
    { PolicyValue::DateTimeSettingsEnabled, &AccessPolicy::dateTimeSettingsEnabledChanged },
    { PolicyValue::DeviceResetEnabled, &AccessPolicy::deviceResetEnabledChanged },
    { PolicyValue::ScreenshotEnabled, &AccessPolicy::screenshotEnabledChanged },
    { PolicyValue::MicrophoneEnabled, &AccessPolicy::microphoneEnabledChanged },
    { PolicyValue::MobileNetworkSettingsEnabled, &AccessPolicy::mobileNetworkSettingsEnabledChanged },
    { PolicyValue::NetworkProxySettingsEnabled, &AccessPolicy::networkProxySettingsEnabledChanged },
    { PolicyValue::NetworkDataCounterSettingsEnabled, &AccessPolicy::networkDataCounterSettingsEnabledChanged },
    { PolicyValue::CallStatisticsSettingsEnabled, &AccessPolicy::callStatisticsSettingsEnabledChanged },
    { PolicyValue::CellularTechnologySettingsEnabled, &AccessPolicy::cellularTechnologySettingsEnabledChanged },
    { PolicyValue::MobileDataAccessPointSettingsEnabled, &AccessPolicy::mobileDataAccessPointSettingsEnabledChanged },
    { PolicyValue::VpnConnectionSettingsEnabled, &AccessPolicy::vpnConnectionSettingsEnabledChanged },
    { PolicyValue::VpnConfigurationSettingsEnabled, &AccessPolicy::vpnConfigurationSettingsEnabledChanged },
    { PolicyValue::BrowserEnabled, &AccessPolicy::browserEnabledChanged },
    { PolicyValue::AccountCreationEnabled, &AccessPolicy::accountCreationEnabledChanged },
    { PolicyValue::RingtoneLevelEnabled, &AccessPolicy::ringtoneLevelEnabledChanged },
    { PolicyValue::AppsupportEnabled, &AccessPolicy::appsupportEnabledChanged },
} };

bool readOnly(const char *setter)
{
    qCWarning(lcSailfishPolicy) << "AccessPolicy::" << setter
                                << ": policies are set by MDM applications; Keel only reads them";
    return false;
}

} // namespace

class AccessPolicyPrivate
{
public:
    std::array<bool, Entries.size()> values {};
    bool privacyModeActive = false;
};

AccessPolicy::AccessPolicy(QObject *parent)
    : QObject(parent)
    , d(new AccessPolicyPrivate)
{
    PolicyStore *store = PolicyStore::instance();
    connect(store, &PolicyStore::changed, this, &AccessPolicy::update);
    connect(store, &PolicyStore::privacyModeActiveChanged, this, &AccessPolicy::update);
    for (std::size_t i = 0; i < Entries.size(); ++i)
        d->values[i] = store->enabled(Entries[i].type);
    d->privacyModeActive = store->privacyModeActive();
}

AccessPolicy::~AccessPolicy()
{
    delete d;
}

void AccessPolicy::update()
{
    const PolicyStore *store = PolicyStore::instance();
    for (std::size_t i = 0; i < Entries.size(); ++i) {
        const bool value = store->enabled(Entries[i].type);
        if (value != d->values[i]) {
            d->values[i] = value;
            emit(this->*Entries[i].changed)();
        }
    }
    if (store->privacyModeActive() != d->privacyModeActive) {
        d->privacyModeActive = store->privacyModeActive();
        emit privacyModeActiveChanged();
    }
}

bool AccessPolicy::privacyModeActive() const
{
    return d->privacyModeActive;
}

bool AccessPolicy::cameraEnabled() const
{
    return d->values[0];
}

bool AccessPolicy::setCameraEnabled(bool /*enabled*/)
{
    return readOnly("setCameraEnabled");
}

bool AccessPolicy::cameraAppEnabled() const
{
    return d->values[1];
}

bool AccessPolicy::setCameraAppEnabled(bool /*enabled*/)
{
    return readOnly("setCameraAppEnabled");
}

bool AccessPolicy::locationSettingsEnabled() const
{
    return d->values[2];
}

bool AccessPolicy::setLocationSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setLocationSettingsEnabled");
}

bool AccessPolicy::osUpdatesEnabled() const
{
    return d->values[3];
}

bool AccessPolicy::setOsUpdatesEnabled(bool /*enabled*/)
{
    return readOnly("setOsUpdatesEnabled");
}

bool AccessPolicy::flightModeToggleEnabled() const
{
    return d->values[4];
}

bool AccessPolicy::setFlightModeToggleEnabled(bool /*enabled*/)
{
    return readOnly("setFlightModeToggleEnabled");
}

bool AccessPolicy::wlanToggleEnabled() const
{
    return d->values[5];
}

bool AccessPolicy::setWlanToggleEnabled(bool /*enabled*/)
{
    return readOnly("setWlanToggleEnabled");
}

bool AccessPolicy::bluetoothToggleEnabled() const
{
    return d->values[6];
}

bool AccessPolicy::setBluetoothToggleEnabled(bool /*enabled*/)
{
    return readOnly("setBluetoothToggleEnabled");
}

bool AccessPolicy::internetSharingEnabled() const
{
    return d->values[7];
}

bool AccessPolicy::setInternetSharingEnabled(bool /*enabled*/)
{
    return readOnly("setInternetSharingEnabled");
}

bool AccessPolicy::sideLoadingSettingsEnabled() const
{
    return d->values[8];
}

bool AccessPolicy::setSideLoadingSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setSideLoadingSettingsEnabled");
}

bool AccessPolicy::developerModeSettingsEnabled() const
{
    return d->values[9];
}

bool AccessPolicy::setDeveloperModeSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setDeveloperModeSettingsEnabled");
}

bool AccessPolicy::applicationInstallationEnabled() const
{
    return d->values[10];
}

bool AccessPolicy::setApplicationInstallationEnabled(bool /*enabled*/)
{
    return readOnly("setApplicationInstallationEnabled");
}

bool AccessPolicy::dateTimeSettingsEnabled() const
{
    return d->values[11];
}

bool AccessPolicy::setDateTimeSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setDateTimeSettingsEnabled");
}

bool AccessPolicy::deviceResetEnabled() const
{
    return d->values[12];
}

bool AccessPolicy::setDeviceResetEnabled(bool /*enabled*/)
{
    return readOnly("setDeviceResetEnabled");
}

bool AccessPolicy::screenshotEnabled() const
{
    return d->values[13];
}

bool AccessPolicy::setScreenshotEnabled(bool /*enabled*/)
{
    return readOnly("setScreenshotEnabled");
}

bool AccessPolicy::microphoneEnabled() const
{
    return d->values[14];
}

bool AccessPolicy::setMicrophoneEnabled(bool /*enabled*/)
{
    return readOnly("setMicrophoneEnabled");
}

bool AccessPolicy::mobileNetworkSettingsEnabled() const
{
    return d->values[15];
}

bool AccessPolicy::setMobileNetworkSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setMobileNetworkSettingsEnabled");
}

bool AccessPolicy::networkProxySettingsEnabled() const
{
    return d->values[16];
}

bool AccessPolicy::setNetworkProxySettingsEnabled(bool /*enabled*/)
{
    return readOnly("setNetworkProxySettingsEnabled");
}

bool AccessPolicy::networkDataCounterSettingsEnabled() const
{
    return d->values[17];
}

bool AccessPolicy::setNetworkDataCounterSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setNetworkDataCounterSettingsEnabled");
}

bool AccessPolicy::callStatisticsSettingsEnabled() const
{
    return d->values[18];
}

bool AccessPolicy::setCallStatisticsSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setCallStatisticsSettingsEnabled");
}

bool AccessPolicy::cellularTechnologySettingsEnabled() const
{
    return d->values[19];
}

bool AccessPolicy::setCellularTechnologySettingsEnabled(bool /*enabled*/)
{
    return readOnly("setCellularTechnologySettingsEnabled");
}

bool AccessPolicy::mobileDataAccessPointSettingsEnabled() const
{
    return d->values[20];
}

bool AccessPolicy::setMobileDataAccessPointSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setMobileDataAccessPointSettingsEnabled");
}

bool AccessPolicy::vpnConnectionSettingsEnabled() const
{
    return d->values[21];
}

bool AccessPolicy::setVpnConnectionSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setVpnConnectionSettingsEnabled");
}

bool AccessPolicy::vpnConfigurationSettingsEnabled() const
{
    return d->values[22];
}

bool AccessPolicy::setVpnConfigurationSettingsEnabled(bool /*enabled*/)
{
    return readOnly("setVpnConfigurationSettingsEnabled");
}

bool AccessPolicy::browserEnabled() const
{
    return d->values[23];
}

bool AccessPolicy::setBrowserEnabled(bool /*enabled*/)
{
    return readOnly("setBrowserEnabled");
}

bool AccessPolicy::accountCreationEnabled() const
{
    return d->values[24];
}

bool AccessPolicy::setAccountCreationEnabled(bool /*enabled*/)
{
    return readOnly("setAccountCreationEnabled");
}

bool AccessPolicy::ringtoneLevelEnabled() const
{
    return d->values[25];
}

bool AccessPolicy::setRingtoneLevelEnabled(bool /*enabled*/)
{
    return readOnly("setRingtoneLevelEnabled");
}

bool AccessPolicy::appsupportEnabled() const
{
    return d->values[26];
}

bool AccessPolicy::setAppsupportEnabled(bool /*enabled*/)
{
    return readOnly("setAppsupportEnabled");
}

} // namespace Sailfish
