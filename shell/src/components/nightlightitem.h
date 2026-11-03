#pragma once

#include <QQuickItem>
#include <QVector3D>
#include <qqml.h>

// Night light: scales the finished frame's colour towards a black body at
// `temperature` kelvin, the way a CRTC gamma ramp would. Drawn as one quad
// blended dst * src, so it costs one full-screen blend and no extra pass.
// Nothing is drawn at 6500 K and above.
class NightLightItem : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal temperature READ temperature WRITE setTemperature NOTIFY temperatureChanged)

  public:
    explicit NightLightItem(QQuickItem *parent = nullptr);

    qreal temperature() const {
        return m_temperature;
    }
    void setTemperature(qreal kelvin);

    // The white point at `kelvin`, gamma-encoded, relative to 6500 K.
    static QVector3D whitePoint(qreal kelvin);

  signals:
    void temperatureChanged();

  protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void     geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

  private:
    qreal m_temperature = 6500;
};
