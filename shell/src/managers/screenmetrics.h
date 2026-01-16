#pragma once

#include <QObject>
#include <QPointer>

class QScreen;

class ScreenMetrics : public QObject {
    Q_OBJECT
    Q_PROPERTY(int width READ width NOTIFY metricsChanged)
    Q_PROPERTY(int height READ height NOTIFY metricsChanged)
    Q_PROPERTY(qreal dpi READ dpi NOTIFY metricsChanged)
    Q_PROPERTY(qreal refreshRate READ refreshRate NOTIFY metricsChanged)
    Q_PROPERTY(qreal devicePixelRatio READ devicePixelRatio NOTIFY metricsChanged)

  public:
    explicit ScreenMetrics(QObject *parent = nullptr);

    int width() const {
        return m_width;
    }
    int height() const {
        return m_height;
    }
    qreal dpi() const {
        return m_dpi;
    }
    qreal refreshRate() const {
        return m_refreshRate;
    }
    qreal devicePixelRatio() const {
        return m_devicePixelRatio;
    }

  signals:
    void metricsChanged();

  private:
    void              attachToScreen(QScreen *screen);
    void              updateFromScreen();
    qreal             computeDpi(QScreen *screen) const;

    QPointer<QScreen> m_screen;
    int               m_width            = 0;
    int               m_height           = 0;
    qreal             m_dpi              = 0.0;
    qreal             m_refreshRate      = 0.0;
    qreal             m_devicePixelRatio = 1.0;
};
