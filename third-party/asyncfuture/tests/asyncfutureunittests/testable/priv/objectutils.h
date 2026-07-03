#ifndef OBJECTUTILS_H
#define OBJECTUTILS_H

#include <QObject>
#include <QString>

namespace Testable {

class ObjectUtils
{
public:

    static QObjectList uniq(const QObjectList& list);

    /// Get all the descendant of an object
    static QObjectList allChildren(QObject* object);

    static QObjectList allChildren(QList<QObject*> objects);

};

}

#endif // OBJECTUTILS_H
