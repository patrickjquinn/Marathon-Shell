#include "trackpadinput.h"

#include <QDir>
#include <QGuiApplication>
#include <QInputMethodQueryEvent>
#include <QPointingDevice>
#include <QSocketNotifier>
#include <QTimer>
#include <QWindow>
#include <qpa/qwindowsysteminterface.h>

#include <cmath>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace {
    // Mouse: px per count, from precise when slow to quick when fast. Speed
    // is in counts per 8 ms, about one report of the 129 Hz sensor.
    constexpr qreal kSlowGain  = 0.7;
    constexpr qreal kGainSlope = 0.35;
    constexpr qreal kMaxSpeed  = 10.0;
    // Gesture: px of scroll per count, and counts per caret step.
    constexpr qreal kScrollGain = 4.0;
    constexpr qreal kCaretStep  = 10.0;

    bool isTrackpad(int fd) {
        char name[128] = {};
        if (ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name) < 0)
            return false;
        unsigned long rel = 0;
        if (ioctl(fd, EVIOCGBIT(EV_REL, sizeof(rel)), &rel) < 0)
            return false;
        return QByteArray(name).contains("trackpad") && (rel & (1UL << REL_X));
    }
} // namespace

TrackpadInput::TrackpadInput(QObject *parent)
    : QObject(parent) {
    m_clock.start();
    m_device = new QPointingDevice(QStringLiteral("BBQX0 trackpad"), 0x7470,
                                   QInputDevice::DeviceType::Mouse,
                                   QPointingDevice::PointerType::Generic,
                                   QInputDevice::Capability::Position |
                                       QInputDevice::Capability::Scroll,
                                   1, 1, QString(), QPointingDeviceUniqueId(), this);
    QWindowSystemInterface::registerInputDevice(m_device);
    open();
}

TrackpadInput::~TrackpadInput() {
    if (m_fd >= 0) {
        ioctl(m_fd, EVIOCGRAB, 0);
        ::close(m_fd);
    }
}

void TrackpadInput::setMode(const QString &mode) {
    if (m_mode == mode)
        return;
    m_mode = mode;
    m_carry = m_steps = QPointF();
    emit modeChanged();
}

void TrackpadInput::setCompositor(QObject *compositor) {
    if (m_compositor == compositor)
        return;
    m_compositor = compositor;
    emit compositorChanged();
}

// The keyboard's driver can load after the shell: look again for a minute.
void TrackpadInput::open() {
    const QStringList nodes = QDir(QStringLiteral("/dev/input"))
                                  .entryList({QStringLiteral("event*")}, QDir::System);
    for (const QString &node : nodes) {
        const QByteArray path = QByteArrayLiteral("/dev/input/") + node.toLocal8Bit();
        const int        fd   = ::open(path.constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0)
            continue;
        // Grabbed, so libinput no longer moves Qt's pointer with it.
        if (isTrackpad(fd) && ioctl(fd, EVIOCGRAB, 1) == 0) {
            m_fd       = fd;
            m_notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
            connect(m_notifier, &QSocketNotifier::activated, this, &TrackpadInput::readEvents);
            emit availableChanged();
            return;
        }
        ::close(fd);
    }
    static int tries = 0;
    if (++tries < 30)
        QTimer::singleShot(2000, this, &TrackpadInput::open);
}

void TrackpadInput::readEvents() {
    input_event events[64];
    const ssize_t n = ::read(m_fd, events, sizeof(events));
    if (n < 0) {
        if (errno == EAGAIN)
            return;
        delete m_notifier;
        m_notifier = nullptr;
        ::close(m_fd);
        m_fd = -1;
        emit availableChanged();
        QTimer::singleShot(2000, this, &TrackpadInput::open);
        return;
    }
    for (ssize_t i = 0; i < n / ssize_t(sizeof(input_event)); ++i) {
        const input_event &e = events[i];
        if (e.type == EV_REL && e.code == REL_X) {
            m_frameDx += e.value;
        } else if (e.type == EV_REL && e.code == REL_Y) {
            m_frameDy += e.value;
        } else if (e.type == EV_KEY && e.code == BTN_LEFT && e.value != 2) {
            button(e.value == 1);
        } else if (e.type == EV_SYN && e.code == SYN_REPORT && (m_frameDx || m_frameDy)) {
            const qint64 now = m_clock.elapsed();
            motion(m_frameDx, m_frameDy, now - m_lastFrameMs);
            m_lastFrameMs = now;
            m_frameDx = m_frameDy = 0;
        }
    }
}

void TrackpadInput::motion(int dx, int dy, qint64 dtMs) {
    if (m_mode == QLatin1String("mouse"))
        moveMouse(dx, dy, dtMs);
    else
        gesture(dx, dy);
}

QWindow *TrackpadInput::window() const {
    if (QWindow *focus = QGuiApplication::focusWindow())
        return focus;
    const auto windows = QGuiApplication::topLevelWindows();
    return windows.isEmpty() ? nullptr : windows.first();
}

void TrackpadInput::moveMouse(int dx, int dy, qint64 dtMs) {
    QWindow *w = window();
    if (!w)
        return;
    if (m_pos.isNull())
        m_pos = QPointF(w->width() / 2.0, w->height() / 2.0);
    // A pause starts a new movement at the slow, precise gain.
    const qreal ms    = dtMs > 100 ? 8.0 : qMax<qreal>(dtMs, 4.0);
    const qreal speed = std::hypot(dx, dy) * 8.0 / ms;
    const qreal gain  = kSlowGain + kGainSlope * qBound<qreal>(0.0, speed - 1.0, kMaxSpeed);
    m_carry += QPointF(dx, dy) * gain;
    const QPointF step(std::trunc(m_carry.x()), std::trunc(m_carry.y()));
    m_carry -= step;
    if (step.isNull())
        return;
    m_pos.setX(qBound<qreal>(0, m_pos.x() + step.x(), w->width() - 1));
    m_pos.setY(qBound<qreal>(0, m_pos.y() + step.y(), w->height() - 1));
    QWindowSystemInterface::handleMouseEvent(w, ulong(m_clock.elapsed()), m_device, m_pos,
                                             w->mapToGlobal(m_pos), m_buttons, Qt::NoButton,
                                             QEvent::MouseMove);
}

bool TrackpadInput::typing() const {
    QObject *focus = QGuiApplication::focusObject();
    if (!focus)
        return false;
    QInputMethodQueryEvent query(Qt::ImEnabled);
    QCoreApplication::sendEvent(focus, &query);
    if (query.value(Qt::ImEnabled).toBool())
        return true;
    bool enabled = false;
    if (m_compositor)
        QMetaObject::invokeMethod(m_compositor, "focusedTextInputEnabled", Qt::DirectConnection,
                                  Q_RETURN_ARG(bool, enabled));
    return enabled;
}

void TrackpadInput::gesture(int dx, int dy) {
    QWindow *w = window();
    if (!w)
        return;
    if (typing()) {
        m_steps += QPointF(dx, dy);
        while (qMax(std::abs(m_steps.x()), std::abs(m_steps.y())) >= kCaretStep) {
            if (std::abs(m_steps.x()) >= std::abs(m_steps.y())) {
                const bool right = m_steps.x() > 0;
                key(right ? Qt::Key_Right : Qt::Key_Left, right ? KEY_RIGHT : KEY_LEFT);
                m_steps.rx() -= right ? kCaretStep : -kCaretStep;
            } else {
                const bool down = m_steps.y() > 0;
                key(down ? Qt::Key_Down : Qt::Key_Up, down ? KEY_DOWN : KEY_UP);
                m_steps.ry() -= down ? kCaretStep : -kCaretStep;
            }
        }
        return;
    }
    m_steps = QPointF();
    // Content follows the finger, as on the touchscreen.
    const QPoint  pixels(qRound(dx * kScrollGain), qRound(dy * kScrollGain));
    const QPointF centre(w->width() / 2.0, w->height() / 2.0);
    QWindowSystemInterface::handleWheelEvent(w, ulong(m_clock.elapsed()), m_device, centre,
                                             w->mapToGlobal(centre), pixels, pixels * 12);
}

void TrackpadInput::button(bool pressed) {
    QWindow *w = window();
    if (!w)
        return;
    if (m_mode != QLatin1String("mouse")) {
        if (pressed)
            key(Qt::Key_Return, KEY_ENTER);
        return;
    }
    m_buttons.setFlag(Qt::LeftButton, pressed);
    if (m_pos.isNull())
        m_pos = QPointF(w->width() / 2.0, w->height() / 2.0);
    QWindowSystemInterface::handleMouseEvent(
        w, ulong(m_clock.elapsed()), m_device, m_pos, w->mapToGlobal(m_pos), m_buttons,
        Qt::LeftButton, pressed ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease);
}

// With the evdev code (+8, as xkb counts), which Wayland clients receive.
void TrackpadInput::key(int qtKey, int evdevCode) {
    QWindow *w = window();
    if (!w)
        return;
    const QString text = qtKey == Qt::Key_Return ? QStringLiteral("\r") : QString();
    QWindowSystemInterface::handleExtendedKeyEvent(w, QEvent::KeyPress, qtKey, Qt::NoModifier,
                                                   quint32(evdevCode + 8), 0, 0, text);
    QWindowSystemInterface::handleExtendedKeyEvent(w, QEvent::KeyRelease, qtKey, Qt::NoModifier,
                                                   quint32(evdevCode + 8), 0, 0, text);
}
