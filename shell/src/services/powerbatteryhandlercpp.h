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

    // Stamp the power key-DOWN time. PowerKeyListener sees every physical
    // press on raw /dev/input, so this is the reliable source of hold
    // duration. handlePowerButtonPress() (fired on key-UP) uses it to
    // recognise a long press and NOT toggle the screen — the long-press
    // gesture belongs to the power menu, and toggling on its release is
    // what blanked the screen the instant the menu appeared.
    void notePowerButtonDown();

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

    // Wall-clock of the most recent power key-DOWN (see notePowerButtonDown).
    // Compared against key-UP time to classify short vs long press. 0 = no
    // press in flight.
    qint64 m_pressDownMs = 0;

    // Hold threshold that promotes a press to a LONG press (power menu). Must
    // match the QML powerButtonTimer interval in MarathonShell.qml so both
    // event paths agree on where short ends and long begins.
    static constexpr qint64 kLongPressMs = 800;
};

#endif
