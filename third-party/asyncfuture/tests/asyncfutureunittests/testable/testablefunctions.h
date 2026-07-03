#pragma once
#include <QObject>
#include <functional>

namespace Testable {

    bool inherited(QObject *object, const QString &className);

    /// Walk on a QML tree structure
    void walk(QObject* object, std::function<bool(QObject*, QObject*)> predicate);

    bool isCI();

}
