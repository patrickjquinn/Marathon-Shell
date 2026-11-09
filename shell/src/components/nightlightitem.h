#pragma once

#include <QQuickItem>
#include <QVector3D>
#include <qqml.h>

// Night light: scales the finished frame's colour towards a black body at
// `temperature` kelvin, the way a CRTC gamma ramp would. Drawn as one quad
// blended dst * src, so it costs one full-screen blend and no extra pass.
// `dim` keeps that share of the light as well, for a panel whose lowest
// backlight level is still too bright. Nothing is drawn at 6500 K and above
// with dim at 1.
class NightLightItem : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(qreal temperature READ temperature WRITE setTemperature NOTIFY temperatureChanged)
    Q_PROPERTY(qreal dim READ dim WRITE setDim NOTIFY dimChanged)

  public:
    explicit NightLightItem(QQuickItem *parent = nullptr);

    qreal temperature() const {
        return m_temperature;
    }
    void  setTemperature(qreal kelvin);
    qreal dim() const {
        return m_dim;
    }
    void setDim(qreal dim);

    // The white point at `kelvin`, gamma-encoded, relative to 6500 K.
    static QVector3D whitePoint(qreal kelvin);

  signals:
    void temperatureChanged();
    void dimChanged();

  protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;
    void     geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;

  private:
    qreal m_temperature = 6500;
    qreal m_dim         = 1;
};
