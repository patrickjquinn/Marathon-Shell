#ifndef AUDIOMANAGERCPP_H
#define AUDIOMANAGERCPP_H

#include <QObject>

class AudioManagerCpp : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY mutedChanged)

public:
    explicit AudioManagerCpp(QObject* parent = nullptr);
    
    bool available() const { return m_available; }
    double volume() const { return m_currentVolume; }
    bool muted() const { return m_muted; }
    
    Q_INVOKABLE void setVolume(double volume);
    Q_INVOKABLE void setMuted(bool muted);

signals:
    void availableChanged();
    void volumeChanged();
    void mutedChanged();

private:
    bool m_available;
    double m_currentVolume;
    bool m_muted;
};

#endif // AUDIOMANAGERCPP_H

