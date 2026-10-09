// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's Sailfish Policy API for Qt 6: the policy types (the same names and
// values as Sailfish's libsailfishpolicy 0.4.26 public header). Also usable
// from C.

#ifndef SAILFISH_POLICYTYPES_H
#define SAILFISH_POLICYTYPES_H

#ifdef __cplusplus
namespace Sailfish::PolicyTypes {
#endif

enum PolicyType {
    Unknown,
    CameraEnabled,
    LocationSettingsEnabled,
    OsUpdatesEnabled,
    SideLoadingSettingsEnabled,
    DeveloperModeSettingsEnabled,
    ApplicationInstallationEnabled,
    WlanToggleEnabled,
    BluetoothToggleEnabled,
    InternetSharingEnabled,
    DeviceResetEnabled,
    ScreenshotEnabled,
    MobileNetworkSettingsEnabled,
    UsbMassStorageEnabled,
    UsbDeveloperModeEnabled,
    UsbMtpEnabled,
    UsbHostEnabled,
    UsbConnectionSharingEnabled,
    UsbDiagnosticModeEnabled,
    UsbAdbEnabled,
    DateTimeSettingsEnabled,
    MicrophoneEnabled,
    FlightModeToggleEnabled,
    NetworkProxySettingsEnabled,
    NetworkDataCounterSettingsEnabled,
    CallStatisticsSettingsEnabled,
    CellularTechnologySettingsEnabled,
    MobileDataAccessPointSettingsEnabled,
    VpnConnectionSettingsEnabled,
    VpnConfigurationSettingsEnabled,
    BrowserEnabled,
    AccountCreationEnabled,
    CameraAppEnabled,
    RingtoneLevelEnabled,
    AppsupportEnabled
};

#ifdef __cplusplus
} // namespace Sailfish::PolicyTypes
#endif

#endif // SAILFISH_POLICYTYPES_H
