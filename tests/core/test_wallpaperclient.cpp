#include <QDBusConnection>
#include <QProcess>
#include <QSignalSpy>
#include <QTest>

#include "wallpaperclient.h"

// Stands in for the shell's org.marathonos.Shell.Wallpaper1.
class FakeWallpapers : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Wallpaper1")

  public slots:
    QVariantList GetWallpapers() {
        return {QVariantMap{{"name", "Dawn"}, {"path", "file:///usr/share/marathon-shell/wallpapers/dawn.svg"},
                            {"isDark", true}}};
    }
};

// Stands in for Settings' wallpaperPath.
class FakeSettings : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString wallpaperPath READ wallpaperPath WRITE setWallpaperPath NOTIFY wallpaperPathChanged)

  public:
    QString wallpaperPath() const {
        return m_path;
    }
    void setWallpaperPath(const QString &p) {
        m_path = p;
        emit wallpaperPathChanged();
    }

  signals:
    void wallpaperPathChanged();

  private:
    QString m_path = QStringLiteral("file:///a.svg");
};

class TestWallpaperClient : public QObject {
    Q_OBJECT

    QProcess daemon;
    QString  address;

  private slots:
    void initTestCase() {
        daemon.start("dbus-daemon", {"--session", "--nofork", "--print-address"});
        QVERIFY(daemon.waitForReadyRead(5000));
        address = QString::fromUtf8(daemon.readLine()).trimmed();
    }
    void cleanupTestCase() {
        daemon.kill();
        daemon.waitForFinished();
    }

    void listsTheShellsWallpapers() {
        QDBusConnection shell = QDBusConnection::connectToBus(address, "shell");
        FakeWallpapers  fake;
        QVERIFY(shell.registerObject("/org/marathonos/Shell/Wallpaper", &fake, QDBusConnection::ExportAllSlots));
        QVERIFY(shell.registerService("org.marathonos.Shell"));
        QDBusConnection client = QDBusConnection::connectToBus(address, "client");
        FakeSettings    settings;
        WallpaperClient wallpapers(&settings, client);
        QTRY_COMPARE(wallpapers.wallpapers().size(), 1);
        QCOMPARE(wallpapers.wallpapers().constFirst().toMap().value("name").toString(), QString("Dawn"));
    }

    void currentAndSetFollowTheSettings() {
        FakeSettings    settings;
        WallpaperClient wallpapers(&settings, QDBusConnection::connectToBus(address, "client2"));
        QCOMPARE(wallpapers.currentWallpaper(), QString("file:///a.svg"));
        QSignalSpy changed(&wallpapers, &WallpaperClient::currentWallpaperChanged);
        wallpapers.setWallpaper(QStringLiteral("file:///b.svg"), true);
        QCOMPARE(settings.wallpaperPath(), QString("file:///b.svg"));
        QCOMPARE(wallpapers.currentWallpaper(), QString("file:///b.svg"));
        QCOMPARE(changed.size(), 1);
    }
};

QTEST_GUILESS_MAIN(TestWallpaperClient)
#include "test_wallpaperclient.moc"
