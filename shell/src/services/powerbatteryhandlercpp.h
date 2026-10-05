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

    // Fallback dedupe window for handlePowerButtonPress, used when
    // PowerKeyListener has not seen a key-DOWN (see m_rawKeySeen). Two event
    // sources fire for one press (QML Keys.onReleased when the shell has
    // focus, AND PowerKeyListener's /dev/input reader); without a dedupe
    // the press would toggle twice — enter Doze then immediately exit
    // again (or vice versa).
    qint64 m_lastPressMs = 0;

    // Wall-clock of the most recent power key-DOWN (see notePowerButtonDown).
    // Compared against key-UP time to classify short vs long press. 0 = no
    // press in flight.
    qint64 m_pressDownMs = 0;

    // Set once PowerKeyListener has reported a key-DOWN. From then on every
    // physical press is stamped in m_pressDownMs, so the press itself is the
    // dedupe key and m_lastPressMs is only the fallback for devices where
    // the raw listener found no power key.
    bool m_rawKeySeen = false;

    // Hold threshold that promotes a press to a LONG press (power menu). Must
    // match the QML powerButtonTimer interval in MarathonShell.qml so both
    // event paths agree on where short ends and long begins.
    static constexpr qint64 kLongPressMs = 800;
};

#endif
