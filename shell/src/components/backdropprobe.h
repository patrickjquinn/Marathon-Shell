#pragma once

#include <QPointer>
#include <QQuickItem>
#include <qqml.h>

class BackdropSampler;

// Whether the frame is light along this item's top and bottom pixel rows.
// One sampler per window reads every probe's rows back from frames the scene
// graph renders anyway, through a pixel buffer and a fence, at most four
// times a second.
class BackdropProbe : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool light READ isLight NOTIFY lightChanged)
    // Until the first reading, and where the frame can't be read (GLES 2).
    Q_PROPERTY(bool fallbackLight READ fallbackLight WRITE setFallbackLight NOTIFY lightChanged)

  public:
    explicit BackdropProbe(QQuickItem *parent = nullptr);
    ~BackdropProbe() override;

    bool isLight() const {
        return m_read ? m_light : m_fallbackLight;
    }
    bool fallbackLight() const {
        return m_fallbackLight;
    }
    void setFallbackLight(bool light);

  signals:
    void lightChanged();

  private:
    friend class BackdropSampler;

    void                      attach(QQuickWindow *window);
    void                      setLight(bool light);

    QPointer<BackdropSampler> m_sampler;
    bool                      m_light         = false;
    bool                      m_read          = false;
    bool                      m_fallbackLight = false;
};
