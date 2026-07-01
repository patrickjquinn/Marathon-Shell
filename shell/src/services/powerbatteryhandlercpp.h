#ifndef POWERBATTERYHANDLERCPP_H
#define POWERBATTERYHANDLERCPP_H

#include <QDateTime>
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

    // Dedupe window for handlePowerButtonPress. Two event sources can
    // fire back-to-back (QML Keys.onReleased when the shell has focus,
    // AND PowerKeyListener's /dev/input reader when a Wayland app
    // subprocess owns focus). Both call this handler; without a dedupe
    // the press would toggle twice — enter Doze then immediately exit
    // again (or vice versa). 200 ms covers the ~1-5 ms typical gap.
    qint64 m_lastPressMs = 0;
};

#endif
