#ifndef DISPLAYMANAGERCPP_H
#define DISPLAYMANAGERCPP_H

#include <QObject>
#include <QString>

class DisplayManagerCpp : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit DisplayManagerCpp(QObject* parent = nullptr);
    
    bool available() const { return m_available; }
    
    Q_INVOKABLE void setBrightness(double brightness);

signals:
    void availableChanged();

private:
    bool m_available;
    QString m_backlightDevice;
    int m_maxBrightness;
    
    bool detectBacklightDevice();
};

#endif // DISPLAYMANAGERCPP_H

