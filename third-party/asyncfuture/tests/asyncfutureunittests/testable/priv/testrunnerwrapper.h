#ifndef TESTRUNNERWRAPPER_H
#define TESTRUNNERWRAPPER_H

#include <QObject>
#include <QVariantMap>
#include "../testrunner.h"

/// Wrapper of TestRunner for QML

class TestRunnerWrapper : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList arguments READ arguments NOTIFY argumentsChanged)
    Q_PROPERTY(QVariantMap config READ config NOTIFY configChanged)

public:
    explicit TestRunnerWrapper(QObject *parent = 0);

    QStringList arguments() const;

    QVariantMap config() const;

public slots:
    /// A dummy function to trigger the creation of TestRunnerWrapper by QML Engine
    /*
    Example:

     Image {
        source: TestRunner.prepare("image://custom/xxx.png");
     }

     Then it will create TestRunner and run the engine hook defined in TestRunner C++ class.
    */
    QString prepare(const QString& dummy) const;

signals:
    void argumentsChanged();

    void configChanged();

private:

};

#endif // TESTRUNNERWRAPPER_H
