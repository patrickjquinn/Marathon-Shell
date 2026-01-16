#ifndef STATUSBARICONSERVICECPP_H
#define STATUSBARICONSERVICECPP_H

#include <QObject>
#include <QString>

class StatusBarIconServiceCpp : public QObject {
    Q_OBJECT

  public:
    explicit StatusBarIconServiceCpp(QObject *parent = nullptr)
        : QObject(parent) {}

    Q_INVOKABLE QString getBatteryIcon(int level, bool isCharging) const;
    Q_INVOKABLE QString getBatteryColor(int level, bool isCharging) const;
    Q_INVOKABLE QString getSignalIcon(int strength) const;
    Q_INVOKABLE qreal   getSignalOpacity(int strength) const;
    Q_INVOKABLE QString getWifiIcon(bool isEnabled, int strength, bool isConnected) const;
    Q_INVOKABLE qreal   getWifiOpacity(bool isEnabled, int strength, bool isConnected) const;
    Q_INVOKABLE QString getBluetoothIcon(bool isEnabled, bool isConnected) const;
    Q_INVOKABLE qreal   getBluetoothOpacity(bool isEnabled, bool isConnected) const;
    Q_INVOKABLE bool    shouldShowAirplaneMode(bool isEnabled) const;
    Q_INVOKABLE bool    shouldShowDnd(bool isEnabled) const;
    Q_INVOKABLE bool    shouldShowBluetooth(bool isEnabled) const;
};

#endif
