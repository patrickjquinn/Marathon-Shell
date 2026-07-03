#include <QMap>
#include <QQuickItem>
#include "objectutils.h"
#include "testablefunctions.h"

using namespace Testable;

QObjectList Testable::ObjectUtils::uniq(const QObjectList &list)
{
    QMap<QObject*, bool> map;
    QObjectList res;

    for (int i = 0 ; i < list.count() ;i++) {
        QObject* object = list.at(i);
        if (!map.contains(object)) {
            res << object;
            map[object] = true;
        }
    }

    return res;

}

QObjectList Testable::ObjectUtils::allChildren(QObject *object)
{
    QObjectList result;

    result << object;

    foreach(QObject* child, object->children()) {
        result.append(allChildren(child));
    }

    if (inherited(object, "QQuickFlickable") || inherited(object, "QQuickWindow")) {
        QQuickItem* contentItem = object->property("contentItem").value<QQuickItem*>();
        if (contentItem) {

            QList<QQuickItem *>items = contentItem->childItems();

            foreach(QQuickItem* item, items) {
                result.append(allChildren(item));
            }

            result.append(allChildren(contentItem));
        }
    }

    return uniq(result);
}

QObjectList Testable::ObjectUtils::allChildren(QList<QObject *> objects)
{
    QObjectList result;

    foreach (QObject* object, objects) {
        result << allChildren(object);
    }

    return uniq(result);
}
