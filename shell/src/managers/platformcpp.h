#ifndef PLATFORMCPP_H
#define PLATFORMCPP_H

#include <QObject>
#include "platform.h"

class PlatformCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool hasHardwareKeyboard READ hasHardwareKeyboard CONSTANT)

  public:
    explicit PlatformCpp(QObject *parent = nullptr)
        : QObject(parent) {}

    bool hasHardwareKeyboard() const {
        return Platform::hasHardwareKeyboard();
    }
};

#endif
