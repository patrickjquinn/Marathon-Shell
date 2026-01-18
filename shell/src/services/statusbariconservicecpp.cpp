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

QString StatusBarIconServiceCpp::getBatteryColor(int level, bool isCharging) const {
    if (isCharging)
        return "#00CCCC";
    if (level <= 10)
        return "#FF4444";
    if (level <= 20)
        return "#FF8800";
    return "#FFFFFF";
}

QString StatusBarIconServiceCpp::getSignalIcon(int strength) const {
    if (strength == 0)
        return "signal-zero";
    if (strength <= 25)
        return "signal-low";
    if (strength <= 50)
        return "signal-medium";
    if (strength <= 75)
        return "signal";
    return "signal-high";
}

qreal StatusBarIconServiceCpp::getSignalOpacity(int strength) const {
    if (strength == 0)
        return 0.3;
    if (strength <= 25)
        return 0.6;
    if (strength <= 50)
        return 0.8;
    if (strength <= 75)
        return 0.9;
    return 1.0;
}

QString StatusBarIconServiceCpp::getWifiIcon(bool isEnabled, int strength, bool isConnected) const {
    if (!isEnabled || !isConnected)
        return "wifi-off";
    if (strength == 0)
        return "wifi-zero";
    if (strength <= 33)
        return "wifi-low";
    if (strength <= 66)
        return "wifi";
    return "wifi-high";
}

qreal StatusBarIconServiceCpp::getWifiOpacity(bool isEnabled, int strength,
                                              bool isConnected) const {
    if (!isEnabled || !isConnected)
        return 0.3;
    if (strength == 0)
        return 0.4;
    if (strength <= 33)
        return 0.6;
    if (strength <= 66)
        return 0.8;
    return 1.0;
}

QString StatusBarIconServiceCpp::getBluetoothIcon(bool isEnabled, bool isConnected) const {
    Q_UNUSED(isEnabled);
    Q_UNUSED(isConnected);
    return "bluetooth";
}

qreal StatusBarIconServiceCpp::getBluetoothOpacity(bool isEnabled, bool isConnected) const {
    if (!isEnabled)
        return 0.3;
    if (isConnected)
        return 1.0;
    return 0.6;
}

bool StatusBarIconServiceCpp::shouldShowAirplaneMode(bool isEnabled) const {
    return isEnabled;
}

bool StatusBarIconServiceCpp::shouldShowDnd(bool isEnabled) const {
    return isEnabled;
}

bool StatusBarIconServiceCpp::shouldShowBluetooth(bool isEnabled) const {
    return isEnabled;
}
