#ifndef HAPTICMANAGER_H
#define HAPTICMANAGER_H

#include <QObject>
#include <QString>

class HapticManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

  public:
    explicit HapticManager(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    bool enabled() const {
        return m_enabled;
    }
    void             setEnabled(bool enabled);

    Q_INVOKABLE void vibrate(int duration = 50);
    Q_INVOKABLE void vibratePattern(const QList<int> &pattern);
    Q_INVOKABLE void cancelVibration();

  signals:
    void availableChanged();
    void enabledChanged();

  private:
    bool    detectVibrator();
    void    writeVibrator(int value);

    bool    m_available;
    bool    m_enabled;
    QString m_vibratorPath;
};

#endif // HAPTICMANAGER_H
