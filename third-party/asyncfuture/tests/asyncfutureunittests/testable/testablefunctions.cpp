#include <QMap>
#include <QQuickItem>
#include "testablefunctions.h"

bool Testable::inherited(QObject *object, const QString &className)
{
    bool res = false;

    const QMetaObject *metaObject = object->metaObject();

    while (metaObject) {
        if (metaObject->className() == className) {
            res = true;
            break;
        }
        metaObject = metaObject->superClass();
    }

    return res;
}

void Testable::walk(QObject *object, std::function<bool (QObject *, QObject*)> predicate)
{
    QMap<QObject*, bool> map;

    std::function<bool(QObject*, QObject*)> _walk;

    _walk = [&](QObject* object, QObject* parent) -> bool {

        if (!object || map[object]) {
            return true;
        }

        map[object] = true;

        if (!predicate(object, parent)) {
            return false;
        }

        if (inherited(object,"QQuickRepeater")) {
            int count = object->property("count").toInt();

            for (int i = 0 ;  i < count ;i++) {
                QQuickItem* item;
                QMetaObject::invokeMethod(object,"itemAt",Qt::DirectConnection,
                                          Q_RETURN_ARG(QQuickItem*,item),
                                          Q_ARG(int,i));

                if (!_walk(item, object)) {
                    return false;
                }
            }

        } else if (inherited(object, "QQuickFlickable") || inherited(object, "QQuickWindow")) {

            QQuickItem* contentItem = object->property("contentItem").value<QQuickItem*>();

            if (contentItem) {
                QList<QQuickItem *>items = contentItem->childItems() ;
                for (int i = 0 ;  i < items.size() ; i++) {
                    if (!_walk(items.at(i) , object)){
                        return false;
                    }
                }
            }
        }

        QObjectList children = object->children();

        for (int i = 0 ; i < children.size();i++) {
            if (!_walk(children.at(i), object)) {
                return false;
            }
        }

        return true;
    };

    _walk(object, 0);
}

bool Testable::isCI()
{
    return (qgetenv("TRAVIS") == "true")  || qgetenv("APPVEYOR") == "True";
}
