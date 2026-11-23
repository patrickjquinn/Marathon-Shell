// Android's touch slop (8 dp, ViewConfiguration.TOUCH_SLOP) at the screen's
// density and a 500 ms hold, as the shell sets for itself, instead of Qt's
// density-blind 10 px and 800 ms. The compositor advertises the panel's
// real size, so the screen's physical DPI is the panel's.
//
// Every Qt app the shell starts also turns its text input off when focus
// leaves a field (TextInputFocus), so the trackpad scrolls again.
#include "services/textinputfocus.h"

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
        if (auto *app = qobject_cast<QGuiApplication *>(QCoreApplication::instance()))
            TextInputFocus::follow(app);
        return new QObject;
    }
};

#include "main.moc"
