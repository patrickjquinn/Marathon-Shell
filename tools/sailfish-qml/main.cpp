// sailfish-qml APP — runs a QML-only Sailfish app from /usr/share/APP/qml/APP.qml
// on Keel, as Sailfish OS's launcher of the same name does.

#include <sailfishapp.h>

#include <QGuiApplication>
#include <QQuickView>

int main(int argc, char *argv[]) {
    if (argc < 2) {
        qCritical("usage: sailfish-qml APP");
        return 2;
    }
    SailfishApp::application(argc, argv);
    QGuiApplication::setApplicationName(QString::fromLocal8Bit(argv[1]));
    QQuickView *view = SailfishApp::createView();
    view->setSource(SailfishApp::pathToMainQml());
    view->show();
    return QGuiApplication::exec();
}
