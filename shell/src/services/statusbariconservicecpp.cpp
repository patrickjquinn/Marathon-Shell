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

QString StatusBarIconServiceCpp::getBatteryColor(int /*level*/, bool /*isCharging*/) const {
    // DS rule (ds-foundations.jsx Color · 'Application rules'):
    // teal is for action only. Battery state is NOT an action, so we
    // never tint the icon teal — the charging glyph itself carries
    // the visual cue. Critical-low / low-warn use the reserved
    // semantic palette (error / sec-amber) but ONLY when the user
    // actually needs to react. We keep the icon text-primary at all
    // sane levels so the status bar reads as quiet chrome.
    return "#F5F5F5"; // MColors.textPrimary
}

QString StatusBarIconServiceCpp::getBatterySemanticColor(int level, bool isCharging) const {
    // For consumers that want to surface the SEMANTIC state (e.g.
    // the Quick Settings tile or Battery settings page), this
    // returns the error/amber/primary mapping the icon-only
    // getBatteryColor() intentionally avoids.
    if (level <= 10 && !isCharging)
        return "#EF4444"; // MColors.error  · critical
    if (level <= 20 && !isCharging)
        return "#C89545"; // MColors.secAmber · low warning
    return "#F5F5F5";     // MColors.textPrimary
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
