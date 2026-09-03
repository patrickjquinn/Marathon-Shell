#pragma once
#include <QObject>

class TestableUtils : public QObject
{
    Q_OBJECT
public:
    explicit TestableUtils(QObject *parent = 0);

signals:

public slots:

    void wait(int timeout = 1000);

    QObject* findChild(QObject*parent, const QString& objectName );
};
