#ifndef INPUTBOOST_H
#define INPUTBOOST_H

#include "marathon-shell-native/src/boost.cxxqt.h"

#include <QEvent>
#include <QObject>

// Every touch, click and key reaches the shell's window first (it is the
// compositor): each raises the CPU clock floor for a while (boost.rs).
class InputBoost : public QObject {
  public:
    using QObject::QObject;

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override {
        if (watched->isWindowType()) {
            switch (event->type()) {
                case QEvent::TouchBegin:
                case QEvent::TouchUpdate:
                case QEvent::MouseButtonPress:
                case QEvent::MouseMove:
                case QEvent::Wheel:
                case QEvent::KeyPress: marathon::boost::input(); break;
                default: break;
            }
        }
        return QObject::eventFilter(watched, event);
    }
};

#endif
