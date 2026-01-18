#pragma once

#include <QObject>
#include <QString>

class QTimer;

class FlashlightManagerCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(int brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(int maxBrightness READ maxBrightness NOTIFY maxBrightnessChanged)
    Q_PROPERTY(QString ledPath READ ledPath NOTIFY ledPathChanged)

  public:
    explicit FlashlightManagerCpp(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    bool enabled() const {
        return m_enabled;
    }
    int brightness() const {
        return m_brightness;
    }
    int maxBrightness() const {
        return m_maxBrightness;
    }
    QString ledPath() const {
        return m_ledPath;
    }

    void             setEnabled(bool enabled);
    void             setBrightness(int value);

    Q_INVOKABLE bool toggle();
    Q_INVOKABLE void pulse(int durationMs);
    Q_INVOKABLE void refresh();

  signals:
    void availableChanged();
    void enabledChanged();
    void brightnessChanged();
    void maxBrightnessChanged();
    void ledPathChanged();
    void errorOccurred(const QString &message);

  private:
    bool    discoverLed();
    int     readMaxBrightness(const QString &ledDir) const;
    bool    writeBrightness(int value) const;

    bool    m_available     = false;
    bool    m_enabled       = false;
    int     m_brightness    = 255;
    int     m_maxBrightness = 255;
    QString m_ledPath;

    QTimer *m_pulseTimer = nullptr;
};
