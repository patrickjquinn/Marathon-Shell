// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// org.nemomobile.lipstick 0.1 (lipstick's launcher types for Qt 6) over a
// temporary applications directory: LauncherItem reads a .desktop file (as
// chum-gui uses it) and launches it through GIO; LauncherModel lists the
// displayable applications, filters by category and follows files being
// added and removed; LauncherWatcherModel follows given files;
// LauncherFolderModel groups items into folders and saves them to
// $XDG_CONFIG_HOME/lipstick/applications.menu.

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

class tst_Lipstick : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void launcherItem();
    void launcherModel();
    void categories();
    void watcherModel();
    void folderModel();

private:
    QString apps() const { return m_root.filePath(QStringLiteral("applications")); }
    void writeDesktop(const QString &name, const QByteArray &body);
    std::unique_ptr<QObject> create(const QByteArray &qml);
    static QString titleAt(QObject *model, int index);

    QTemporaryDir m_root;
    QQmlEngine m_engine;
};

void tst_Lipstick::writeDesktop(const QString &name, const QByteArray &body)
{
    QFile f(apps() + QLatin1Char('/') + name);
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("[Desktop Entry]\nType=Application\n" + body);
}

std::unique_ptr<QObject> tst_Lipstick::create(const QByteArray &qml)
{
    QQmlComponent c(&m_engine);
    c.setData("import QtQuick 2.0\nimport org.nemomobile.lipstick 0.1\n" + qml, QUrl(QStringLiteral("inline.qml")));
    std::unique_ptr<QObject> o(c.create());
    if (!o)
        qWarning().noquote() << c.errorString();
    return o;
}

QString tst_Lipstick::titleAt(QObject *model, int index)
{
    QObject *item = nullptr;
    QMetaObject::invokeMethod(model, "get", Q_RETURN_ARG(QObject *, item), Q_ARG(int, index));
    return item ? item->property("title").toString() : QString();
}

void tst_Lipstick::initTestCase()
{
    QVERIFY(m_root.isValid());
    QVERIFY(QDir().mkpath(apps()));
    m_engine.addImportPath(QStringLiteral(KEEL_QML_DIR));
    writeDesktop(QStringLiteral("alpha.desktop"),
                 "Name=Alpha\nIcon=alpha\nExec=/bin/true\nCategories=Utility;\n");
    writeDesktop(QStringLiteral("beta.desktop"),
                 "Name=Beta\nName[fi]=Beeta\nIcon=beta\nExec=/bin/true\nCategories=Network;\n"
                 "[X-Sailjail]\nPermissions=Internet\n");
    writeDesktop(QStringLiteral("hidden.desktop"), "Name=Hidden\nExec=/bin/true\nNoDisplay=true\n");
}

void tst_Lipstick::launcherItem()
{
    const QString marker = m_root.filePath(QStringLiteral("launched"));
    writeDesktop(QStringLiteral("launch.desktop"),
                 "Name=Launch\nNoDisplay=true\nExec=touch " + marker.toUtf8() + "\n");
    auto item = create("LauncherItem { }");
    QVERIFY(item);
    QVERIFY(!item->property("isValid").toBool());
    item->setProperty("filePath", apps() + QStringLiteral("/beta.desktop"));
    QVERIFY(item->property("isValid").toBool());
    QCOMPARE(item->property("titleUnlocalized").toString(), QStringLiteral("Beta"));
    QCOMPARE(item->property("iconId").toString(), QStringLiteral("beta"));
    QCOMPARE(item->property("fileID").toString(), QStringLiteral("beta.desktop"));
    QCOMPARE(item->property("desktopCategories").toStringList(), QStringList { QStringLiteral("Network") });
    QVERIFY(item->property("isSandboxed").toBool());
    QVERIFY(item->property("shouldDisplay").toBool());

    // Launched through GIO's GDesktopAppInfo, as lipstick does without
    // contentaction.
    item->setProperty("filePath", apps() + QStringLiteral("/launch.desktop"));
    QVERIFY(!item->property("shouldDisplay").toBool());
    QMetaObject::invokeMethod(item.get(), "launchApplication");
    QTRY_VERIFY(QFile::exists(marker));
}

void tst_Lipstick::launcherModel()
{
    auto model = create(R"(LauncherModel { directories: [")" + apps().toUtf8() + R"("] })");
    QVERIFY(model);
    QTRY_COMPARE(model->property("itemCount").toInt(), 2); // not the NoDisplay ones
    QStringList titles { titleAt(model.get(), 0), titleAt(model.get(), 1) };
    titles.sort();
    QCOMPARE(titles, (QStringList { QStringLiteral("Alpha"), QStringLiteral("Beta") }));

    writeDesktop(QStringLiteral("gamma.desktop"), "Name=Gamma\nExec=/bin/true\n");
    QTRY_COMPARE_WITH_TIMEOUT(model->property("itemCount").toInt(), 3, 10000);
    QVERIFY(QFile::remove(apps() + QStringLiteral("/gamma.desktop")));
    QTRY_COMPARE_WITH_TIMEOUT(model->property("itemCount").toInt(), 2, 10000);
}

void tst_Lipstick::categories()
{
    auto model = create(R"(LauncherModel { directories: [")" + apps().toUtf8() + R"("]; categories: ["Network"] })");
    QVERIFY(model);
    QTRY_COMPARE(model->property("itemCount").toInt(), 1);
    QCOMPARE(titleAt(model.get(), 0), QStringLiteral("Beta"));
}

void tst_Lipstick::watcherModel()
{
    auto model = create(R"(LauncherWatcherModel { filePaths: [")" + apps().toUtf8() + R"(/alpha.desktop"] })");
    QVERIFY(model);
    QTRY_COMPARE(model->property("itemCount").toInt(), 1);
    QCOMPARE(titleAt(model.get(), 0), QStringLiteral("Alpha"));
}

void tst_Lipstick::folderModel()
{
    auto model = create(R"(LauncherFolderModel {
    directories: [")" + apps().toUtf8() + R"("]
    function makeFolder() { return createFolder(0, "Tools") }
    function moveInto(item, folder) { return moveToFolder(item, folder) }
})");
    QVERIFY(model);
    QTRY_COMPARE(model->property("itemCount").toInt(), 2);
    QVariant folderValue;
    QVERIFY(QMetaObject::invokeMethod(model.get(), "makeFolder", Q_RETURN_ARG(QVariant, folderValue)));
    auto *folder = folderValue.value<QObject *>();
    QVERIFY(folder);
    QCOMPARE(folder->property("title").toString(), QStringLiteral("Tools"));
    // The item that was at the index goes into the new folder.
    QCOMPARE(model->property("itemCount").toInt(), 2);
    QCOMPARE(folder->property("itemCount").toInt(), 1);
    QObject *item = nullptr;
    QMetaObject::invokeMethod(model.get(), "get", Q_RETURN_ARG(QObject *, item), Q_ARG(int, 1));
    QVERIFY(item);
    QVariant moved;
    QVERIFY(QMetaObject::invokeMethod(model.get(), "moveInto", Q_RETURN_ARG(QVariant, moved),
                                      Q_ARG(QVariant, QVariant::fromValue(item)),
                                      Q_ARG(QVariant, QVariant::fromValue(folder))));
    QVERIFY(moved.toBool());
    QCOMPARE(folder->property("itemCount").toInt(), 2);
    QCOMPARE(model->property("itemCount").toInt(), 1);
    // Saved for the next start.
    const QString menu = qEnvironmentVariable("XDG_CONFIG_HOME") + QStringLiteral("/lipstick/applications.menu");
    QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(menu), 10000);
    QFile f(menu);
    QVERIFY(f.open(QIODevice::ReadOnly));
    const QByteArray xml = f.readAll();
    QVERIFY2(xml.contains("Tools"), xml.constData());
}

int main(int argc, char **argv)
{
    // Before lipstick's plugin computes its configuration directory.
    QTemporaryDir config;
    qputenv("XDG_CONFIG_HOME", config.path().toLocal8Bit());
    QGuiApplication app(argc, argv);
    tst_Lipstick test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_lipstick.moc"
