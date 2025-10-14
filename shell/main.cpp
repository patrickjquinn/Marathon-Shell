#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QDebug>
#include <QQmlContext>

#include "src/desktopfileparser.h"

#ifdef HAVE_WAYLAND
#include "src/waylandcompositor.h"
#endif

int main(int argc, char *argv[])
{
    QGuiApplication::setApplicationName("Marathon Shell");
    QGuiApplication::setOrganizationName("Marathon OS");
    
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("Basic");
    
#ifdef HAVE_WAYLAND
    qmlRegisterType<WaylandCompositor>("MarathonOS.Wayland", 1, 0, "WaylandCompositor");
    qDebug() << "Wayland Compositor support enabled";
#else
    qDebug() << "Wayland Compositor support disabled (not available on this platform)";
#endif
    
    QQmlApplicationEngine engine;
    
    // Register DesktopFileParser as a singleton accessible from QML
    DesktopFileParser *desktopFileParser = new DesktopFileParser(&app);
    engine.rootContext()->setContextProperty("DesktopFileParserCpp", desktopFileParser);
    
    // Add QML import paths for modules
    engine.addImportPath("qrc:/");
    engine.addImportPath(":/");
    
    // Add build directory path for MarathonUI modules
    QString buildPath = QCoreApplication::applicationDirPath() + "/../../../qml";
    engine.addImportPath(buildPath);
    qDebug() << "Added QML import path:" << buildPath;
    
    const QUrl url(QStringLiteral("qrc:/MarathonOS/Shell/qml/Main.qml"));
    
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
        &app, [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                qCritical() << "Failed to load QML";
                QCoreApplication::exit(-1);
            }
        }, Qt::QueuedConnection);
    
    engine.load(url);
    
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "No root QML objects";
        return -1;
    }
    
    qDebug() << "Marathon OS Shell started";
    return app.exec();
}

