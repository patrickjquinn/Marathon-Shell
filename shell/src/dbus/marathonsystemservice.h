#ifndef MARATHONSYSTEMSERVICE_H
#define MARATHONSYSTEMSERVICE_H

#include <QObject>
#include <QDBusContext>
#include <QDBusConnection>

class PowerManagerCpp;
class NetworkManagerCpp;
class DisplayManagerCpp;
class AudioManagerCpp;

class MarathonSystemService : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathon.SystemService")

    Q_PROPERTY(int BatteryLevel READ batteryLevel NOTIFY BatteryChanged)
    Q_PROPERTY(bool BatteryCharging READ batteryCharging NOTIFY BatteryChanged)
    Q_PROPERTY(QString BatteryState READ batteryState NOTIFY BatteryChanged)
    Q_PROPERTY(bool NetworkConnected READ networkConnected NOTIFY NetworkChanged)
    Q_PROPERTY(QString NetworkType READ networkType NOTIFY NetworkChanged)
    Q_PROPERTY(int SignalStrength READ signalStrength NOTIFY NetworkChanged)
    Q_PROPERTY(int DisplayBrightness READ displayBrightness WRITE setDisplayBrightness NOTIFY
                   displayBrightnessChanged)
    Q_PROPERTY(bool DisplayAutoRotate READ displayAutoRotate WRITE setDisplayAutoRotate NOTIFY
                   displayAutoRotateChanged)
    Q_PROPERTY(int DisplayOrientation READ displayOrientation NOTIFY DisplayOrientationChanged)

  public:
    explicit MarathonSystemService(PowerManagerCpp *power, NetworkManagerCpp *network,
                                   DisplayManagerCpp *display, AudioManagerCpp *audio,
                                   QObject *parent = nullptr);
    ~MarathonSystemService();

    bool    registerService();

    int     batteryLevel() const;
    bool    batteryCharging() const;
    QString batteryState() const;
    bool    networkConnected() const;
    QString networkType() const;
    int     signalStrength() const;
    int     displayBrightness() const;
    bool    displayAutoRotate() const;
    int     displayOrientation() const;

    void    setDisplayBrightness(int brightness);
    void    setDisplayAutoRotate(bool enabled);

  public slots:
    QString GetDeviceModel();
    QString GetOSVersion();
    int     GetUptime();
    int     GetCPUUsage();
    int     GetMemoryUsage();
    int     GetTotalMemory();
    bool    SetDisplayBrightness(int brightness);
    bool    SetDisplayAutoRotate(bool enabled);
    void    HapticFeedback(const QString &type);

  signals:
    void BatteryChanged(int level, bool charging);
    void NetworkChanged(bool connected, const QString &type);
    void DisplayOrientationChanged(int orientation);
    void displayBrightnessChanged();
    void displayAutoRotateChanged();

  private:
    PowerManagerCpp   *m_power;
    NetworkManagerCpp *m_network;
    DisplayManagerCpp *m_display;
    AudioManagerCpp   *m_audio;
};

#endif // MARATHONSYSTEMSERVICE_H
