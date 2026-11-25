#ifndef EINKINPUT_H
#define EINKINPUT_H

#include "marathon-shell-native/src/eink.cxxqt.h"

#include <QEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QObject>
#include <QPointerEvent>

// The e-paper waveform policy (eink.rs) hears input as the compositor
// receives it, before any item: the panel goes to its fast waveform on the
// touch-down itself, not after the first moved frames.
class EinkInput : public QObject {
  public:
    using QObject::QObject;

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (!watched->isWindowType())
            return QObject::eventFilter(watched, event);
        const auto at = [event](auto report) {
            const auto *pointer = static_cast<QPointerEvent *>(event);
            if (pointer->pointCount() > 0) {
                const QPointF p = pointer->points().constFirst().globalPosition();
                report(float(p.x()), float(p.y()));
            }
        };
        switch (event->type()) {
            case QEvent::TouchBegin:
            case QEvent::MouseButtonPress: at(marathon::eink::press); break;
            case QEvent::TouchUpdate: at(marathon::eink::motion); break;
            case QEvent::MouseMove:
                if (static_cast<QMouseEvent *>(event)->buttons() != Qt::NoButton)
                    at(marathon::eink::motion);
                break;
            case QEvent::TouchEnd:
            case QEvent::TouchCancel:
            case QEvent::MouseButtonRelease: marathon::eink::release(); break;
            case QEvent::Wheel: marathon::eink::scroll(); break;
            case QEvent::KeyPress: {
                const int key = static_cast<QKeyEvent *>(event)->key();
                // KEY_REFRESH, as xkb (XF86Reload) or Qt's evdev map names it.
                if (key == Qt::Key_Reload || key == Qt::Key_Refresh)
                    marathon::eink::refresh();
                else
                    marathon::eink::key();
                break;
            }
            default: break;
        }
        return QObject::eventFilter(watched, event);
    }
};

#endif
