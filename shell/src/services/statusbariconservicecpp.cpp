#include "statusbariconservicecpp.h"

QString StatusBarIconServiceCpp::getBatteryIcon(int level, bool isCharging) const {
    if (isCharging)
        return "battery-charging";
    if (level <= 10)
        return "battery-warning";
    if (level <= 25)
        return "battery-low";
    if (level <= 50)
        return "battery-medium";
    return "battery-full";
}

// Strength is carried by the glyph, never by opacity: dimmed icons fall
// below 3:1 on the bar and the steps can't be told apart.
QString StatusBarIconServiceCpp::getSignalIcon(int strength) const {
    if (strength == 0)
        return "cell-signal-none";
    if (strength <= 25)
        return "cell-signal-low";
    if (strength <= 50)
        return "cell-signal-medium";
    if (strength <= 75)
        return "cell-signal-high";
    return "cell-signal-full";
}

QString StatusBarIconServiceCpp::getWifiIcon(bool isEnabled, int strength, bool isConnected) const {
    if (!isEnabled || !isConnected)
        return "wifi-slash";
    if (strength <= 33)
        return "wifi-low";
    if (strength <= 66)
        return "wifi-medium";
    return "wifi-high";
}

QString StatusBarIconServiceCpp::getBluetoothIcon(bool isEnabled, bool isConnected) const {
    Q_UNUSED(isEnabled);
    return isConnected ? "bluetooth-connected" : "bluetooth";
}

bool StatusBarIconServiceCpp::shouldShowAirplaneMode(bool isEnabled) const {
    return isEnabled;
}

bool StatusBarIconServiceCpp::shouldShowDnd(bool isEnabled) const {
    return isEnabled;
}
