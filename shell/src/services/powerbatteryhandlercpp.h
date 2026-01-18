#ifndef POWERBATTERYHANDLERCPP_H
#define POWERBATTERYHANDLERCPP_H

#include <QObject>
#include <QPointer>

class PowerPolicyController;
class DisplayPolicyController;
class DisplayManagerCpp;
class HapticManager;

class PowerBatteryHandlerCpp : public QObject {
    Q_OBJECT

  public:
    explicit PowerBatteryHandlerCpp(PowerPolicyController   *powerPolicy,
                                    DisplayPolicyController *displayPolicy,
                                    DisplayManagerCpp *displayManager, HapticManager *haptics,
                                    QObject *parent = nullptr);

    Q_INVOKABLE void handlePowerButtonPress(bool sessionLocked, bool screenOnHint = true);

  signals:
    void lockRequested();

  private:
    void                              turnScreenOn();
    void                              turnScreenOff();

    QPointer<PowerPolicyController>   m_powerPolicy;
    QPointer<DisplayPolicyController> m_displayPolicy;
    QPointer<DisplayManagerCpp>       m_displayManager;
    QPointer<HapticManager>           m_haptics;
};

#endif
