// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Written for Keel from the public SailfishApp API; no libsailfishapp code.

#include "sailfishapp.h"

#include "keellauncher.h"
#include "keellauncher_p.h"
#include "qt5source.h"

#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLocale>
#include <QLoggingCategory>
#include <QQmlDebuggingEnabler>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickView>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSize>
#include <QTimer>
#include <QWindow>
#include <QTranslator>

#include <atomic>
#include <cstdio>
#include <ctime>
#include <functional>
#include <memory>

namespace {

// Window size for desktop runs when the QML sets none: a phone in portrait,
// small enough for a desktop screen.
constexpr QSize kDesktopPhoneSize(540, 960);

QString appName()
{
    QString name = QCoreApplication::applicationName();
    if (name.isEmpty() && !QCoreApplication::arguments().isEmpty())
        name = QFileInfo(QCoreApplication::arguments().constFirst()).fileName();
    return name;
}

QString dataDir()
{
    const QString overridden = qEnvironmentVariable("KEEL_SAILFISHAPP_DATADIR");
    if (!overridden.isEmpty())
        return QDir::cleanPath(overridden);
    return QStringLiteral(KEEL_SAILFISHAPP_SHARE_DIR "/") + appName();
}

// Answers numerus qsTr() strings in English when no catalog does: it is
// installed before every other translator, so Qt asks it last.
class EnglishPluralTranslator : public QTranslator
{
public:
    using QTranslator::QTranslator;
    QString translate(const char *context, const char *sourceText, const char *disambiguation,
                      int n) const override
    {
        Q_UNUSED(context)
        Q_UNUSED(disambiguation)
        if (n < 0 || !sourceText)
            return QString();
        return Keel::detail::englishPlural(QString::fromUtf8(sourceText), n);
    }
    bool isEmpty() const override { return false; }
};

} // namespace

QString Keel::detail::englishPlural(const QString &source, int n)
{
    static const QRegularExpression alternative(QStringLiteral("\\(([^()|]*)\\|([^()|]*)\\)"));
    const bool one = n == 1;
    QString out = source;
    bool changed = false;
    if (out.contains(QLatin1String("(s)"))) {
        out.replace(QLatin1String("(s)"), one ? QString() : QStringLiteral("s"));
        changed = true;
    }
    QRegularExpressionMatch m;
    while ((m = alternative.match(out)).hasMatch()) {
        out.replace(m.capturedStart(), m.capturedLength(), m.captured(one ? 1 : 2));
        changed = true;
    }
    return changed ? out : QString();
}

void Keel::detail::installEnglishPlurals(QCoreApplication *app)
{
    static bool installed = false;
    if (installed || !app)
        return;
    installed = true;
    // One per process; QTranslator's destructor uninstalls it if the
    // application object still exists at exit.
    static EnglishPluralTranslator translator;
    QCoreApplication::installTranslator(&translator);
}

void Keel::detail::installTranslations(QCoreApplication *app)
{
    installEnglishPlurals(app);
    const QString dir = dataDir() + QStringLiteral("/translations");
    const QString base = appName();
    // <appname>.qm (engineering English for id-based translations) is the
    // fallback. Qt searches the most recently installed translator first,
    // so it is installed before the localised one takes effect below.
    auto *fallback = new QTranslator(app);
    if (fallback->load(base, dir))
        QCoreApplication::installTranslator(fallback);
    else
        delete fallback;
    auto *localised = new QTranslator(app);
    if (localised->load(QLocale(), base, QStringLiteral("-"), dir))
        QCoreApplication::installTranslator(localised);
    else
        delete localised;
}

namespace SailfishApp {

QGuiApplication *application(int &argc, char **argv)
{
    // Boosted (booster-keel), or a second call: the existing application.
    if (auto *existing = qobject_cast<QGuiApplication *>(QCoreApplication::instance())) {
        // An app that made its own application object (a Rust main) still
        // gets English plurals; its own catalogs, installed later, come first.
        Keel::detail::installEnglishPlurals(existing);
        return existing;
    }
    // Direct mode on Sailfish (or keel-shell, or a desktop window).
    Keel::prepareEnvironment();
    Keel::detail::prepareApplicationDefaults();
    auto *app = new QGuiApplication(argc, argv);
    if (QCoreApplication::applicationName().isEmpty() && argc > 0 && argv[0])
        QCoreApplication::setApplicationName(QFileInfo(QString::fromLocal8Bit(argv[0])).fileName());
    Keel::detail::installTranslations(app);
    return app;
}

Q_LOGGING_CATEGORY(lcWarmUp, "keel.warmup")

/// KEEL_STARTUP_TRACE=1: the monotonic time (seconds, as Python's
/// time.monotonic()) of the app's first frame on stderr, as
/// "keel-startup: first frame <t>", for measuring launch times (direct and
/// boosted alike). Off unless set.
void traceFirstFrame()
{
    if (!qEnvironmentVariableIsSet("KEEL_STARTUP_TRACE"))
        return;
    struct Tracer : QObject
    {
        std::atomic_bool done = false;
        bool eventFilter(QObject *watched, QEvent *event) override
        {
            auto *window = qobject_cast<QQuickWindow *>(watched);
            if (event->type() == QEvent::Show && window && !window->property("keelCover").toBool()) {
                // On the render thread, when the frame is swapped: stamped
                // there, not when the GUI thread gets to a queued call.
                connect(window, &QQuickWindow::frameSwapped, this, [this] {
                    if (done.exchange(true))
                        return;
                    timespec ts;
                    clock_gettime(CLOCK_MONOTONIC, &ts);
                    fprintf(stderr, "keel-startup: first frame %ld.%06ld\n", long(ts.tv_sec), ts.tv_nsec / 1000);
                    QMetaObject::invokeMethod(this, [this] {
                        qApp->removeEventFilter(this);
                        deleteLater();
                    }, Qt::QueuedConnection);
                }, Qt::DirectConnection);
            }
            return false;
        }
    };
    qApp->installEventFilter(new Tracer);
}

/// Shortly after start-up, compiles the app's own QML files one at a time
/// on the QML loader thread, so that the first push of each page does not
/// pay for loading its types and the Silica components it uses (measured on
/// the Jolla Phone: about 40 ms less on the UI thread at the first push of
/// Shoal Migrate's first page). Nothing is instantiated. KEEL_QML_WARMUP=0
/// turns it off.
void warmUpAppQml(QQuickView *view)
{
    if (qEnvironmentVariableIsSet("KEEL_QML_WARMUP") && qEnvironmentVariableIntValue("KEEL_QML_WARMUP") == 0)
        return;
    // A timer, not the view's first frame: an app may show its own window
    // (Keel's ApplicationWindow) instead of drawing into this view.
    QTimer::singleShot(1500, view, [view]() {
        auto files = std::make_shared<QStringList>();
        // The directory the app's main QML was loaded from: the view's
        // source, or the QML context of a window the app made itself
        // (an app may pass its own path instead of using dataDir()).
        QString mainFile = view->source().toLocalFile();
        if (mainFile.isEmpty()) {
            for (QWindow *w : QGuiApplication::topLevelWindows()) {
                if (QQmlContext *c = QQmlEngine::contextForObject(w)) {
                    if (c->baseUrl().isLocalFile()) {
                        mainFile = c->baseUrl().toLocalFile();
                        break;
                    }
                }
            }
        }
        if (mainFile.isEmpty())
            return;
        const QDir root = QFileInfo(mainFile).dir();
        QDirIterator it(root.path(), {QStringLiteral("*.qml")},
                        QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString f = QFileInfo(it.next()).canonicalFilePath();
            if (f != QFileInfo(mainFile).canonicalFilePath())
                files->append(f);
        }
        auto next = std::make_shared<std::function<void()>>();
        *next = [view, files, next]() {
            if (files->isEmpty())
                return;
            auto *component = new QQmlComponent(view->engine(), QUrl::fromLocalFile(files->takeFirst()),
                                                QQmlComponent::Asynchronous, view);
            const auto done = [view, component, next]() {
                if (component->isLoading())
                    return;
                // Kept (parented to the view): Qt drops a compiled type
                // from its cache once nothing refers to it.
                qCDebug(lcWarmUp) << "compiled" << component->url().fileName() << component->status();
                QTimer::singleShot(0, view, [next]() { (*next)(); });
            };
            if (component->isLoading())
                QObject::connect(component, &QQmlComponent::statusChanged, component, done);
            else
                done();
        };
        (*next)();
    });
}

QQuickView *createView()
{
    // The QML debug server for KEEL_QML_PROFILE (keellauncher.cpp); it needs
    // the application object, which exists by now.
    if (const int port = qEnvironmentVariableIntValue("KEEL_QML_PROFILE"); port > 0)
        QQmlDebuggingEnabler::startTcpDebugServer(port, QQmlDebuggingEnabler::DoNotWaitForClient);
    // Boosted: the booster's view, whose engine already has Sailfish.Silica
    // and Keel loaded and their common types compiled.
    QQuickView *view = Keel::detail::takeBoosterView();
    if (!view)
        view = new QQuickView;
    view->setResizeMode(QQuickView::SizeRootObjectToView);
    // Silica windows are translucent; Lipstick (direct mode) or keel-shell
    // composes the ambience wallpaper behind the app. The Keel
    // ApplicationWindow draws its own background on a desktop.
    QSurfaceFormat format = view->format();
    format.setAlphaBufferSize(8);
    view->setFormat(format);
    view->setColor(Qt::transparent);
    view->setTitle(appName());
    // The app's QML is Qt 5 Sailfish QML: what Qt 6 cannot compile of it
    // (keel/qt5compat/src/qt5source.h) is loaded rewritten. Only the app's
    // own data directory, never Keel's or Qt's modules; code that compiles
    // on Qt 6 is never changed. KEEL_QT5COMPAT_SOURCE=0 turns it off.
    KeelQt5Compat::installSourceCompat(view->engine(), {dataDir()});
    warmUpAppQml(view);
    traceFirstFrame();
    return view;
}

QUrl pathTo(const QString &filename)
{
    return QUrl::fromLocalFile(QDir::cleanPath(dataDir() + QLatin1Char('/') + filename));
}

QUrl pathToMainQml()
{
    return pathTo(QStringLiteral("qml/") + appName() + QStringLiteral(".qml"));
}

int main(int &argc, char **argv)
{
    QGuiApplication *app = application(argc, argv);
    const std::unique_ptr<QQuickView> view(createView());
    QObject::connect(view->engine(), &QQmlEngine::quit, app, &QCoreApplication::quit);
    QObject::connect(view->engine(), &QQmlEngine::exit, app, &QCoreApplication::exit);
    view->setSource(pathToMainQml());
    if (view->status() == QQuickView::Error)
        return 1;
    // Full screen on a phone; on a desktop a phone-shaped window unless the
    // QML set a size.
    Keel::showMainWindow(view.get(), kDesktopPhoneSize);
    return QGuiApplication::exec();
}

} // namespace SailfishApp
