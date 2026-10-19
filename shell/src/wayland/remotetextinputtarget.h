#pragma once

#include <QString>

class QObject;
class QWaylandCompositor;

namespace RemoteTextInputTarget {
    // The app id of the window Marathon's keyboard types into when object has
    // Qt's focus: a surface item's own, or, unless object is a text field of
    // the shell's, the window with the seat's keyboard focus (a Waydroid
    // window can hold the keyboard without Qt focus).
    QString appIdOf(QObject *object, QWaylandCompositor *compositor);
} // namespace RemoteTextInputTarget
