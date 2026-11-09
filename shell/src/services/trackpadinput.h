#ifndef TRACKPADINPUT_H
#define TRACKPADINPUT_H

#include <QElapsedTimer>
#include <QObject>
#include <QPointF>
#include <QPointer>

class QPointingDevice;
class QSocketNotifier;
class QTimer;
class QWindow;

// The keyboard's optical trackpad ("BBQX0 trackpad"), read here rather than by
// libinput, whose desktop-mouse acceleration suits it badly.
//   mode "mouse":   it moves the pointer, with a speed curve and sub-pixel
//                   steps; the press is the left button.
//   mode "gesture": swipes scroll what is under focus, or move the caret
//                   while a field takes text; the press is Enter.
class TrackpadInput : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString mode READ mode WRITE setMode NOTIFY modeChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // In use now or within the last moment: the touchscreen's bottom edge
    // sits just above it, where a thumb on the trackpad grazes the glass.
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)
    // The shell's compositor: whether the focused app takes text.
    Q_PROPERTY(QObject *compositor READ compositor WRITE setCompositor NOTIFY compositorChanged)

  public:
    explicit TrackpadInput(QObject *parent = nullptr);
    ~TrackpadInput() override;

    QString mode() const {
        return m_mode;
    }
    void setMode(const QString &mode);
    bool available() const {
        return m_fd >= 0;
    }
    bool active() const {
        return m_active;
    }
    QObject *compositor() const {
        return m_compositor;
    }
    void setCompositor(QObject *compositor);

  signals:
    void modeChanged();
    void availableChanged();
    void activeChanged();
    void compositorChanged();

  private:
    void              open();
    void              readEvents();
    void              motion(int dx, int dy, qint64 dtMs);
    void              button(bool pressed);
    void              moveMouse(int dx, int dy, qint64 dtMs);
    void              gesture(int dx, int dy);
    bool              typing() const;
    void              key(int qtKey, int evdevCode);
    QWindow          *window() const;

    int               m_fd       = -1;
    QSocketNotifier  *m_notifier = nullptr;
    QTimer           *m_idle     = nullptr;
    bool              m_active   = false;
    QPointingDevice  *m_device = nullptr;
    QPointer<QObject> m_compositor;
    QString           m_mode = QStringLiteral("gesture");
    QPointF           m_pos;
    QPointF           m_carry;
    QPointF           m_steps;
    Qt::MouseButtons  m_buttons;
    QElapsedTimer     m_clock;
    qint64            m_lastFrameMs = 0;
    int               m_frameDx     = 0;
    int               m_frameDy     = 0;
};

#endif
