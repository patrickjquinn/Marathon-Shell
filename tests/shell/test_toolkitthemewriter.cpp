#include <QTest>

#include "toolkittheme.h"
#include "toolkitthemewriter.h"

class TestToolkitThemeWriter : public QObject {
    Q_OBJECT

    QTemporaryDir m_dir;

    QString       config() const {
        return m_dir.filePath(QStringLiteral("config"));
    }
    QString data() const {
        return m_dir.filePath(QStringLiteral("data"));
    }
    static QByteArray read(const QString &path) {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
    }
    static void put(const QString &path, const QByteArray &bytes) {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile f(path);
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(bytes);
    }

  private slots:
    void init() {
        QDir(config()).removeRecursively();
        QDir(data()).removeRecursively();
    }

    void writesEveryFileWhenAbsent() {
        const ToolkitThemeWriter writer(config(), data());
        QVERIFY(!writer.gtk3ThemeInstalled());
        writer.write(QColor(0x7d, 0xf0, 0xd4), true);
        QCOMPARE(QString::fromUtf8(read(config() + "/gtk-4.0/gtk.css")),
                 ToolkitTheme::gtk4Css(QColor(0x7d, 0xf0, 0xd4), true));
        QVERIFY(read(data() + "/themes/Marathon/gtk-3.0/gtk.css").contains("gtk-contained.css"));
        QVERIFY(read(data() + "/themes/Marathon-dark/gtk-3.0/gtk.css")
                    .contains("gtk-contained-dark.css"));
        QVERIFY(writer.gtk3ThemeInstalled());
    }

    void followsTheAmbience() {
        const ToolkitThemeWriter writer(config(), data());
        writer.write(QColor(0x7d, 0xf0, 0xd4), true);
        writer.write(QColor(0xff, 0x80, 0x00), false);
        QVERIFY(
            read(config() + "/gtk-4.0/gtk.css").contains("@define-color accent_bg_color #ff8000;"));
    }

    void neverReplacesTheUsersOwnCss() {
        const QString css = config() + "/gtk-4.0/gtk.css";
        put(css, "window { background: hotpink; }\n");
        QVERIFY(!ToolkitThemeWriter::ours(css));
        ToolkitThemeWriter(config(), data()).write(QColor(0x7d, 0xf0, 0xd4), true);
        QCOMPARE(read(css), QByteArray("window { background: hotpink; }\n"));
    }

    void markerMustBeTheFirstLine() {
        const QString css = config() + "/gtk-4.0/gtk.css";
        put(css, QByteArray("/* mine */\n") + ToolkitTheme::kMarker + "\n");
        QVERIFY(!ToolkitThemeWriter::ours(css));
        put(css, QByteArray(ToolkitTheme::kMarker) + "\nold\n");
        QVERIFY(ToolkitThemeWriter::ours(css));
    }
};

QTEST_GUILESS_MAIN(TestToolkitThemeWriter)
#include "test_toolkitthemewriter.moc"
