#ifndef POWERKEYLISTENER_H
#define POWERKEYLISTENER_H

#include <QObject>
#include <QList>
#include <utility>

class QSocketNotifier;

/*
 * PowerKeyListener
 *
 * Watches every /dev/input/event* node whose KEY bitmask advertises KEY_POWER
 * and emits powerKeyPressed() on every key-down event. The Librem 5 exposes
 * two power-key sources (PMIC + SoC SNVS); both fire on a press, so the
 * listener attaches to all of them and emits once per fd.
 *
 * logind has HandlePowerKey=ignore on this image (50-marathon.conf), so the
 * shell is the only consumer of these events. No grab is taken — we share
 * the device with anything else that may need it.
 */
class PowerKeyListener : public QObject {
    Q_OBJECT

  public:
    explicit PowerKeyListener(QObject *parent = nullptr);
    ~PowerKeyListener() override;

  signals:
    // device = "<name> (<path>)" of the input node the press came from.
    void powerKeyPressed(const QString &device);
    void powerKeyReleased(const QString &device);

  private slots:
    void onFdReadable(int fd);

  private:
    struct Watch {
        int              fd;
        QString          name;
        QString          path;
        QSocketNotifier *notifier;
    };

    QList<Watch>                       m_watches;

    QList<std::pair<QString, QString>> discoverPowerKeyDevices() const; // (path, name)
    bool                               openDevice(const QString &path, const QString &name);
    void                               closeAll();
};

#endif
