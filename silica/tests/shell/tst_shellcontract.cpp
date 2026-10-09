// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Client side of the keel-shell contract (keel/shell/PROTOCOL.md), tested
// against FakeShell with the sample app from tests/qml/compatapp.
//
// KEEL_TEST_MODE selects the environment the app starts in:
//   shell   - full keel-shell environment and peer D-Bus server
//   nodbus  - KEEL_SHELL=1 but KEEL_SHELL_DBUS unset (graceful degradation)
//   noshell - plain desktop run, no KEEL_* variables at all

#include "fakeshell.h"

#include <QGuiApplication>
#include <QQmlProperty>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QWindow>

namespace {

struct ShowRecord
{
    QPointer<QWindow> window;
    QString titleAtShow;
    bool transient = false;
    QSize sizeAtShow;
};

class ShowRecorder : public QObject
{
public:
    QList<ShowRecord> shows;

protected:
    bool eventFilter(QObject *o, QEvent *e) override
    {
        if (e->type() == QEvent::Show) {
            if (auto *w = qobject_cast<QWindow *>(o))
                shows.append({ w, w->title(), w->transientParent() != nullptr, w->size() });
        }
        return false;
    }
};

QString mode()
{
    const QString m = qEnvironmentVariable("KEEL_TEST_MODE");
    return m.isEmpty() ? QStringLiteral("shell") : m;
}

const char kMarker[] = "keel:cover";

} // namespace

// Records each value of an object's `status` property as it changes.
class StatusRecorder : public QObject
{
    Q_OBJECT
public:
    explicit StatusRecorder(QObject *target)
        : m_target(target)
    {
        QQmlProperty(target, QStringLiteral("status")).connectNotifySignal(this, SLOT(record()));
    }
    QList<int> seen;

private slots:
    void record() { seen.append(m_target->property("status").toInt()); }

private:
    QObject *m_target;
};

class tst_ShellContract : public QObject
{
    Q_OBJECT

public:
    tst_ShellContract(FakeShell *shell, ShowRecorder *recorder)
        : m_shell(shell)
        , m_recorder(recorder)
    {
    }

private slots:
    void initTestCase();
    void environment();
    void connection();
    void initialAmbienceAndScale();
    void coverWindow();
    void coverStatus();
    void coverSize();
    void coverAction();
    void orientation();
    void activation();
    void ambienceChanged();
    void closeRequested();
    void cleanupTestCase();

private:
    QVariant probe(const char *expr);
    QQuickItem *root() const { return m_view->rootObject(); }
    QQuickItem *coverItem() const { return root()->property("_coverItem").value<QQuickItem *>(); }
    QList<ShowRecord> coverShows() const;

    FakeShell *m_shell;
    ShowRecorder *m_recorder;
    QQuickView *m_view = nullptr;
};

QVariant tst_ShellContract::probe(const char *expr)
{
    QQmlComponent c(m_view->engine());
    c.setData(QByteArray("import QtQuick 2.0\nimport Keel 1.0\nimport Sailfish.Silica 1.0\n"
                         "QtObject { property var v: ")
                  + expr + " }",
              QUrl(QStringLiteral("probe.qml")));
    std::unique_ptr<QObject> o(c.create());
    if (!o) {
        qWarning() << c.errorString();
        return QVariant();
    }
    return o->property("v");
}

QList<ShowRecord> tst_ShellContract::coverShows() const
{
    QList<ShowRecord> out;
    for (const ShowRecord &r : m_recorder->shows)
        if (r.titleAtShow == QLatin1String(kMarker) || r.titleAtShow.startsWith(QLatin1String(kMarker) + QLatin1Char(':')))
            out.append(r);
    return out;
}

void tst_ShellContract::initTestCase()
{
    m_view = new QQuickView;
    m_view->engine()->addImportPath(QStringLiteral(KEEL_QML_DIR));
    m_view->setResizeMode(QQuickView::SizeRootObjectToView);
    m_view->resize(540, 960);
    m_view->setSource(QUrl::fromLocalFile(QStringLiteral(KEEL_COMPATAPP_DIR "/harbour-keelsample.qml")));
    QVERIFY2(m_view->status() == QQuickView::Ready, qPrintable(m_view->errors().isEmpty() ? QString()
                                                                    : m_view->errors().constFirst().toString()));
    m_view->show();
    QVERIFY(QTest::qWaitForWindowExposed(m_view));
    QTRY_COMPARE(root()->property("pageStack").value<QObject *>()->property("busy").toBool(), false);
}

void tst_ShellContract::environment()
{
    // keel-shell sets QT_ENABLE_HIGHDPI_SCALING=0: Qt draws 1:1 and Silica
    // sizes come from Theme.pixelRatio.
    QCOMPARE(m_view->devicePixelRatio(), 1.0);
    QCOMPARE(probe("Shell.underShell").toBool(), mode() != QLatin1String("noshell"));
    QCOMPARE(probe("Shell.coverEnabled").toBool(), mode() != QLatin1String("noshell"));
}

void tst_ShellContract::connection()
{
    if (mode() != QLatin1String("shell")) {
        QCOMPARE(probe("Shell.connected").toBool(), false);
        QCOMPARE(probe("Shell.protocolVersion").toInt(), 0);
        QCOMPARE(probe("Shell.coverStatus").toInt(), 0);
        return;
    }
    QVERIFY(m_shell->clientConnected());
    QCOMPARE(probe("Shell.connected").toBool(), true);
    QTRY_COMPARE(probe("Shell.protocolVersion").toInt(), 1);
    QTRY_COMPARE(probe("Shell.dpi").toInt(), 401);
}

void tst_ShellContract::initialAmbienceAndScale()
{
    if (mode() == QLatin1String("noshell")) {
        QCOMPARE(probe("Theme.pixelRatio").toReal(), 1.0);
        QCOMPARE(probe("Theme.paddingLarge").toReal(), 24.0);
        QCOMPARE(probe("Theme.colorScheme").toInt(), 0);
        return;
    }
    // From KEEL_AMBIENCE_* / KEEL_SILICA_* (set in main()).
    QCOMPARE(probe("Theme.highlightColor").value<QColor>(), QColor(QStringLiteral("#11aa22")));
    QCOMPARE(probe("Theme.pixelRatio").toReal(), 1.5);
    // Silica's z1.5 value (measured on the Jolla Phone), not 24 * 1.5.
    QCOMPARE(probe("Theme.paddingLarge").toReal(), 40.0);
    QCOMPARE(probe("Theme.itemSizeSmall").toReal(), 120.0);
}

void tst_ShellContract::coverWindow()
{
    const QList<ShowRecord> covers = coverShows();
    if (mode() == QLatin1String("noshell")) {
        QVERIFY(covers.isEmpty());
        QCOMPARE(root()->property("_coverWindow").value<QObject *>(), nullptr);
        return;
    }
    QCOMPARE(covers.size(), 1);
    const ShowRecord &r = covers.constFirst();
    // PROTOCOL.md section 3: marker title set before show(), marker + ":" +
    // app name, top level (never a transient), sized by the app.
    QCOMPARE(r.titleAtShow, QStringLiteral("keel:cover:keelsample"));
    QVERIFY(!r.transient);
    QVERIFY(r.window);
    QVERIFY(r.window != m_view);
    const QSizeF expected(qRound(234 * 1.5), qRound(374 * 1.5));
    QCOMPARE(QSizeF(r.window->size()), expected);
    QCOMPARE(QSizeF(r.sizeAtShow), expected);
    QVERIFY(!m_view->title().startsWith(QLatin1String(kMarker)));
    // The cover's QML is inside that window and binds to the app's state.
    QTRY_VERIFY(coverItem());
    QCOMPARE(coverItem()->window(), r.window.data());
    QCOMPARE(coverItem()->objectName(), QStringLiteral("cover"));
}

void tst_ShellContract::coverStatus()
{
    if (mode() != QLatin1String("shell")) {
        if (coverItem())
            QCOMPARE(coverItem()->property("status").toInt(), 0);
        return;
    }
    QQuickItem *cover = coverItem();
    QVERIFY(cover);
    QCOMPARE(cover->property("status").toInt(), 0); // Cover.Inactive
    // Every status the cover passes through, as an app's onStatusChanged sees it.
    StatusRecorder recorder(cover);
    QList<int> &seen = recorder.seen;
    QMetaObject::invokeMethod(m_shell->object(), "setCoverStatus", Q_ARG(int, 1));
    QTRY_COMPARE(cover->property("status").toInt(), 2); // Cover.Active
    QCOMPARE(seen, (QList<int> { 1, 2 })); // Activating, Active
    seen.clear();
    QMetaObject::invokeMethod(m_shell->object(), "setCoverStatus", Q_ARG(int, 0));
    QTRY_COMPARE(cover->property("status").toInt(), 0);
    QCOMPARE(seen, (QList<int> { 3, 0 })); // Deactivating, Inactive
}

void tst_ShellContract::coverSize()
{
    QQuickItem *cover = coverItem();
    if (!cover || !cover->window())
        QSKIP("no cover window in this mode");
    QWindow *w = cover->window();
    const QSize large = w->size();
    QCOMPARE(cover->property("size").toInt(), 0); // Cover.Large
    // The compositor gives the cover window a small cover's size.
    w->resize(large.width() * 148 / 234, large.height() * 237 / 374);
    QTRY_COMPARE(cover->property("size").toInt(), 1); // Cover.Small
    w->resize(large);
    QTRY_COMPARE(cover->property("size").toInt(), 0);
}

void tst_ShellContract::coverAction()
{
    if (mode() == QLatin1String("noshell"))
        return;
    QQuickItem *cover = coverItem();
    QVERIFY(cover);
    QWindow *w = cover->window();
    QVERIFY(w);
    auto *notes = root()->property("notes").value<QObject *>();
    const int before = notes->property("count").toInt();
    // keel-shell forwards taps on the Lipstick cover as ordinary input to the
    // cover surface; the single action fills the action area.
    auto *area = cover->property("coverActionArea").value<QQuickItem *>();
    QVERIFY(area);
    const QPointF p = area->mapToScene(QPointF(area->width() / 2, area->height() / 2));
    QTest::mouseClick(w, Qt::LeftButton, Qt::NoModifier, p.toPoint());
    QTRY_COMPARE(notes->property("count").toInt(), before + 1);
    QCOMPARE(root()->property("lastAction").toString(), QStringLiteral("added From cover"));
    if (mode() == QLatin1String("shell"))
        QTRY_COMPARE(m_shell->object()->activateCalls(), 1); // the action called app.activate()
}

void tst_ShellContract::orientation()
{
    if (mode() != QLatin1String("shell")) {
        QCOMPARE(root()->property("orientation").toInt(), 1); // Orientation.Portrait
        return;
    }
    QMetaObject::invokeMethod(m_shell->object(), "setOrientation", Q_ARG(int, 90));
    QTRY_COMPARE(root()->property("orientation").toInt(), 2); // Orientation.Landscape
    QTRY_VERIFY(!m_shell->object()->contentOrientations().isEmpty());
    QTRY_COMPARE(m_shell->object()->contentOrientations().constLast(), 90);
    QMetaObject::invokeMethod(m_shell->object(), "setOrientation", Q_ARG(int, 0));
    QTRY_COMPARE(root()->property("orientation").toInt(), 1);
    QTRY_COMPARE(m_shell->object()->contentOrientations().constLast(), 0);
}

void tst_ShellContract::activation()
{
    if (mode() != QLatin1String("shell")) {
        // Without a shell, activate() falls back to raising the Qt window.
        QMetaObject::invokeMethod(root(), "activate");
        return;
    }
    QCOMPARE(root()->property("applicationActive").toBool(), true);
    QMetaObject::invokeMethod(m_shell->object(), "setActive", Q_ARG(bool, false));
    QTRY_COMPARE(root()->property("applicationActive").toBool(), false);
    QMetaObject::invokeMethod(m_shell->object(), "setActive", Q_ARG(bool, true));
    QTRY_COMPARE(root()->property("applicationActive").toBool(), true);
    const int before = m_shell->object()->activateCalls();
    QMetaObject::invokeMethod(root(), "activate");
    QTRY_COMPARE(m_shell->object()->activateCalls(), before + 1);
}

void tst_ShellContract::ambienceChanged()
{
    if (mode() != QLatin1String("shell"))
        return;
    QVariantMap ambience;
    ambience.insert(QStringLiteral("/desktop/jolla/theme/color/highlight"), QStringLiteral("#ff0000"));
    ambience.insert(QStringLiteral("/desktop/jolla/theme/color_scheme"), QStringLiteral("darkonlight"));
    QMetaObject::invokeMethod(m_shell->object(), "setAmbience", Q_ARG(QVariantMap, ambience));
    QTRY_COMPARE(probe("Theme.highlightColor").value<QColor>(), QColor(Qt::red));
    QTRY_COMPARE(probe("Theme.colorScheme").toInt(), 1); // Theme.DarkOnLight
    // rgba() applies to the new ambience colour.
    QCOMPARE(probe("Theme.rgba(Theme.highlightColor, 0.5)").value<QColor>().name(QColor::HexArgb),
             QStringLiteral("#80ff0000"));
}

void tst_ShellContract::closeRequested()
{
    if (mode() != QLatin1String("shell"))
        return;
    QSignalSpy quit(m_view->engine(), &QQmlEngine::quit);
    QMetaObject::invokeMethod(m_shell->object(), "requestClose");
    QTRY_COMPARE(quit.count(), 1);
}

void tst_ShellContract::cleanupTestCase()
{
    delete m_view;
    m_view = nullptr;
}

int main(int argc, char **argv)
{
    // Everything keel-shell puts in the app environment must be there
    // before QGuiApplication and before the Keel module is first imported.
    qputenv("QT_ENABLE_HIGHDPI_SCALING", "0");
    const QString m = mode();
    QTemporaryDir socketDir;
    std::unique_ptr<FakeShell> shell;
    if (m != QLatin1String("noshell")) {
        qputenv("KEEL_SHELL", "1");
        qputenv("KEEL_SHELL_PROTOCOL", "1");
        qputenv("KEEL_SHELL_COVER_TITLE", kMarker);
        qputenv("KEEL_SHELL_COVER_ENABLED", "1");
        qputenv("KEEL_SHELL_DPI", "401");
        qputenv("KEEL_AMBIENCE_KEYS", "/desktop/jolla/theme/color/highlight:/desktop/sailfish/silica/theme_pixel_ratio");
        qputenv("KEEL_AMBIENCE_COLOR_HIGHLIGHT", "#11aa22");
        qputenv("KEEL_SILICA_THEME_PIXEL_RATIO", "1.5");
    } else {
        for (const char *v : { "KEEL_SHELL", "KEEL_SHELL_DBUS", "KEEL_SHELL_COVER_TITLE", "KEEL_SHELL_COVER_ENABLED",
                               "KEEL_AMBIENCE_KEYS" })
            qunsetenv(v);
    }
    qunsetenv("KEEL_SHELL_DBUS");

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("keelsample"));
    ShowRecorder recorder;
    app.installEventFilter(&recorder);

    if (m == QLatin1String("shell")) {
        shell = std::make_unique<FakeShell>(socketDir.path());
        qputenv("KEEL_SHELL_DBUS", shell->address().toUtf8());
    }

    tst_ShellContract test(shell.get(), &recorder);
    return QTest::qExec(&test, argc, argv);
}

#include "tst_shellcontract.moc"
