// Android's touch slop (8 dp, ViewConfiguration.TOUCH_SLOP) at the screen's
// density and a 500 ms hold, as the shell sets for itself, instead of Qt's
// density-blind 10 px and 800 ms. The compositor advertises the panel's
// real size, so the screen's physical DPI is the panel's.
#include <QGenericPlugin>
#include <QGuiApplication>
#include <QScreen>
#include <QStyleHints>

class TouchHints : public QGenericPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QGenericPluginFactoryInterface_iid FILE "marathon-touch-hints.json")

  public:
    QObject *create(const QString &, const QString &) override {
        QStyleHints *hints = QGuiApplication::styleHints();
        if (const QScreen *screen = QGuiApplication::primaryScreen())
            hints->setStartDragDistance(qMax(10, qRound(8 * screen->physicalDotsPerInch() / 160)));
        hints->setMousePressAndHoldInterval(500);
        return new QObject;
    }
};

#include "main.moc"
