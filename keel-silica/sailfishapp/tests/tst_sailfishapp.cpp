// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include <keellauncher.h>
#include <sailfishapp.h>

#include <QGuiApplication>
#include <QProcess>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QTest>
#include <QWindow>

class tst_SailfishApp : public QObject
{
    Q_OBJECT

private slots:
    void applicationIsSingleAndNamed();
    void englishPlurals();
    void pathToUsesDataDir();
    void pathToDefaultsToShareAppName();
    void pathToMainQml();
    void createView();
    void mainRunsTheApp();
    void mainFailsWithoutQml();
    void headlessForKeelActions();
};

void tst_SailfishApp::applicationIsSingleAndNamed()
{
    int argc = 1;
    char name[] = "other";
    char *argv[] = { name, nullptr };
    QGuiApplication *app = SailfishApp::application(argc, argv);
    QCOMPARE(app, qGuiApp);
    QCOMPARE(QCoreApplication::applicationName(), QStringLiteral("tst_sailfishapp"));
}

void tst_SailfishApp::englishPlurals()
{
    // Installed by SailfishApp::application(), also for an application the
    // app made itself (as here): numerus qsTr() strings without a catalog.
    int argc = 1;
    char name[] = "other";
    char *argv[] = { name, nullptr };
    SailfishApp::application(argc, argv);
    const auto tr = [](const char *s, int n) { return QCoreApplication::translate("Page", s, nullptr, n); };
    QCOMPARE(tr("%n update(s) available", 1), QStringLiteral("1 update available"));
    QCOMPARE(tr("%n update(s) available", 2), QStringLiteral("2 updates available"));
    QCOMPARE(tr("%n update(s) available", 0), QStringLiteral("0 updates available"));
    QCOMPARE(tr("unread message(s)", 1), QStringLiteral("unread message"));
    QCOMPARE(tr("Trial: %n day(s) left", 30), QStringLiteral("Trial: 30 days left"));
    QCOMPARE(tr("%n (entry|entries)", 1), QStringLiteral("1 entry"));
    QCOMPARE(tr("%n (entry|entries)", 4), QStringLiteral("4 entries"));
    // Not numerus, or no marker: untouched.
    QCOMPARE(tr("Delete (s)elected", -1), QStringLiteral("Delete (s)elected"));
    QCOMPARE(tr("%n imported", 1), QStringLiteral("1 imported"));
    QCOMPARE(tr("Pick (one|two)", -1), QStringLiteral("Pick (one|two)"));
}

void tst_SailfishApp::pathToUsesDataDir()
{
    QCOMPARE(SailfishApp::pathTo(QStringLiteral("qml/pages/First.qml")),
             QUrl::fromLocalFile(QStringLiteral(KEEL_TEST_DATA "/qml/pages/First.qml")));
    QVERIFY(SailfishApp::pathTo(QString()).isLocalFile());
}

void tst_SailfishApp::pathToDefaultsToShareAppName()
{
    const QByteArray saved = qgetenv("KEEL_SAILFISHAPP_DATADIR");
    qunsetenv("KEEL_SAILFISHAPP_DATADIR");
    QCOMPARE(SailfishApp::pathTo(QStringLiteral("images/a.png")),
             QUrl::fromLocalFile(QStringLiteral(KEEL_SHARE_DIR "/tst_sailfishapp/images/a.png")));
    qputenv("KEEL_SAILFISHAPP_DATADIR", saved);
}

void tst_SailfishApp::pathToMainQml()
{
    QCOMPARE(SailfishApp::pathToMainQml(), SailfishApp::pathTo(QStringLiteral("qml/tst_sailfishapp.qml")));
}

void tst_SailfishApp::createView()
{
#ifdef KEEL_TEST_NO_SILICA
    QSKIP("Sailfish.Silica is not built (KEEL_BUILD_SILICA=OFF)");
#endif
    std::unique_ptr<QQuickView> view(SailfishApp::createView());
    QVERIFY(view);
    QCOMPARE(view->resizeMode(), QQuickView::SizeRootObjectToView);
    QCOMPARE(view->color(), QColor(Qt::transparent));
    QVERIFY(view->format().alphaBufferSize() >= 8);
    view->engine()->addImportPath(QStringLiteral(KEEL_QML_DIR));
    view->setSource(SailfishApp::pathToMainQml());
    QVERIFY2(view->status() == QQuickView::Ready,
             qPrintable(view->errors().isEmpty() ? QString() : view->errors().constFirst().toString()));
    view->resize(540, 960);
    view->show();
    QVERIFY(QTest::qWaitForWindowExposed(view.get()));
    QCOMPARE(view->rootObject()->objectName(), QStringLiteral("main"));
    QCOMPARE(view->rootObject()->width(), 540.0); // sized to the view
    auto *stack = view->rootObject()->property("pageStack").value<QObject *>();
    QTRY_COMPARE(stack->property("depth").toInt(), 1);
}

void tst_SailfishApp::mainRunsTheApp()
{
#ifdef KEEL_TEST_NO_SILICA
    QSKIP("Sailfish.Silica is not built (KEEL_BUILD_SILICA=OFF)");
#endif
    QProcess p;
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("KEEL_SAILFISHAPP_DATADIR"), QStringLiteral(KEEL_TEST_DATA));
    env.insert(QStringLiteral("QML_IMPORT_PATH"), QStringLiteral(KEEL_QML_DIR));
    p.setProcessEnvironment(env);
    p.start(QStringLiteral(KEEL_PROBE), {});
    QVERIFY(p.waitForFinished(30000));
    QCOMPARE(p.exitStatus(), QProcess::NormalExit);
    // 42: the main QML loaded, its initial page was pushed and
    // Qt.application.name came from argv[0].
    QCOMPARE(p.exitCode(), 42);
}

void tst_SailfishApp::mainFailsWithoutQml()
{
    QProcess p;
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("KEEL_SAILFISHAPP_DATADIR"), QStringLiteral(KEEL_TEST_DATA "/missing"));
    p.setProcessEnvironment(env);
    p.start(QStringLiteral(KEEL_PROBE), {});
    QVERIFY(p.waitForFinished(30000));
    QCOMPARE(p.exitCode(), 1);
}

// Keel Actions' D-Bus activation (ADR-0018): no window is shown.
void tst_SailfishApp::headlessForKeelActions()
{
    QVERIFY(!Keel::headless());
    qputenv("KEEL_ACTIONS_HEADLESS", "1");
    QVERIFY(Keel::headless());
    QWindow window;
    Keel::showMainWindow(&window);
    QVERIFY(!window.isVisible());
    qunsetenv("KEEL_ACTIONS_HEADLESS");
}

int main(int argc, char **argv)
{
    qputenv("KEEL_SAILFISHAPP_DATADIR", KEEL_TEST_DATA);
    QGuiApplication *app = SailfishApp::application(argc, argv);
    tst_SailfishApp test;
    const int rc = QTest::qExec(&test, argc, argv);
    delete app;
    return rc;
}

#include "tst_sailfishapp.moc"
