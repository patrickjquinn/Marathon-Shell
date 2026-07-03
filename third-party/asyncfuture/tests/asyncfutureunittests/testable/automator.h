#pragma once
#include <QObject>
#include <QQmlApplicationEngine>
#include <QPointer>
#include <QQuickItem>
#include <QPointF>
#include <QElapsedTimer>

/// Automator provides an interface to manipulate UI object loaded by QQmlApplicationEngine

class Automator : public QObject
{
    Q_OBJECT
public:
    Automator(QQmlApplicationEngine* engine = 0);

    QQmlApplicationEngine *engine() const;

    void setEngine(QQmlApplicationEngine *engine);

    static void wait(int timeout);

    QObject* findObject(QString objectName);

    QObjectList findObjects(QString objectName);

    bool waitExists(QString objectName,int timeout = 1000);

    // If the point paremter is missed. It will hit the center point
    bool click(QQuickItem *item,  int delay = 100, QPointF point = QPointF());

    bool click(QQuickItem *item, QString childObjectName);

    bool click(QString name, int delay = 100, QPointF point = QPointF());

    // Click on the view directly
    bool click(int interval= 100 ,QPointF = QPointF());

    bool anyError() const;

    void setAnyError(bool anyError);

    QObject* obtainSingletonObject(QString package, int versionMajor, int versionMinor, QString typeName);

    bool waitUntil(QString objectName, QString property, QVariant value, int timeout = 1000);

    static bool waitUntil(QObject *object, QString property, QVariant value,int timeout = 1000);

    /// Wait until a signal is emietted from object
    static bool waitUntilSignal(QObject *object, const char* signal, int timeout = 1000);

    template <typename Functor>
    bool waitUntil(Functor functor, int timeout = -1) {
        QElapsedTimer time;
        time.start();

        while (!functor()) {
            Automator::wait(10);
            if (timeout > 0 && time.elapsed() > timeout) {
                return false;
            }
        }
        return true;
    }

private slots:
    void onWarnings(QList<QQmlError>);

private:

    QObjectList findObjects(QObject* object, QString objectName);

    QPointer<QQmlApplicationEngine> m_engine;

    QQuickWindow* window();

    bool m_anyError;
};

