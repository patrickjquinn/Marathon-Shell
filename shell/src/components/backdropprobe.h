#pragma once

#include <QPointer>
#include <QQuickItem>
#include <QTimer>
#include <qqml.h>

class BackdropReader;

// Whether the frame is light along this item's top and bottom pixel rows.
// The rows are read back from frames the scene graph renders anyway, through
// a pixel buffer and a fence, at most four times a second.
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

  protected:
    void releaseResources() override;

  private:
    void                   attach(QQuickWindow *window);
    void                   sync();
    void                   cleanup();
    void                   setLight(bool light);
    void                   followUp();

    BackdropReader        *m_reader = nullptr;
    QPointer<QQuickWindow> m_window;
    QTimer                 m_followUp;
    bool                   m_light         = false;
    bool                   m_read          = false;
    bool                   m_fallbackLight = false;
};
