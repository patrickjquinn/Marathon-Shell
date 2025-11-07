// Quick test to see QWaylandOutput defaults
#include <QGuiApplication>
#include <QtWaylandCompositor/QWaylandCompositor>
#include <QtWaylandCompositor/QWaylandQuickOutput>
#include <QQuickWindow>
#include <QDebug>

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    QQuickWindow window;
    window.resize(540, 1140);
    
    QWaylandCompositor compositor;
    QWaylandQuickOutput *output = new QWaylandQuickOutput(&compositor, &window);
    output->setSizeFollowsWindow(true);
    
    qDebug() << "QWaylandOutput defaults:";
    qDebug() << "  scaleFactor():" << output->scaleFactor();
    qDebug() << "  physicalSize():" << output->physicalSize();
    qDebug() << "  window()->size():" << output->window()->size();
    qDebug() << "  window()->devicePixelRatio():" << window.devicePixelRatio();
    
    return 0;
}
