#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include "filechoosermodel.h"

class TestFileChooserModel : public QObject {
    Q_OBJECT

    QTemporaryDir home;

    void touch(const QString &relative, qint64 ageSecs = 0) {
        const QString path = home.filePath(relative);
        QVERIFY(QDir().mkpath(QFileInfo(path).absolutePath()));
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write("x");
        file.flush();
        file.setFileTime(QDateTime::currentDateTime().addSecs(-ageSecs), QFileDevice::FileModificationTime);
    }

    static QStringList names(const FileChooserModel &model) {
        QStringList out;
        for (int i = 0; i < model.rowCount(); ++i)
            out << model.data(model.index(i), FileChooserModel::NameRole).toString();
        return out;
    }

  private slots:
    void initTestCase() {
        qputenv("HOME", home.path().toUtf8());
        qputenv("XDG_DATA_HOME", home.filePath(QStringLiteral(".local/share")).toUtf8());
        qputenv("XDG_CONFIG_HOME", home.filePath(QStringLiteral(".config")).toUtf8());
        touch(QStringLiteral("Pictures/beach.png"), 60);
        touch(QStringLiteral("Pictures/Holiday/sea.jpg"), 120);
        touch(QStringLiteral("Pictures/notes.txt"), 30);
        touch(QStringLiteral("Pictures/.hidden.png"));
        touch(QStringLiteral("Pictures/anim.webp"));
        touch(QStringLiteral("Documents/report.pdf"), 10);
        touch(QStringLiteral("Documents/old.pdf"), qint64{90} * 24 * 3600);
    }

    void foldersComeFirstThenNames() {
        FileChooserModel model;
        model.setFolder(home.filePath(QStringLiteral("Pictures")));
        QCOMPARE(names(model), QStringList({"Holiday", "anim.webp", "beach.png", "notes.txt"}));
        QVERIFY(model.data(model.index(0), FileChooserModel::IsDirRole).toBool());
        QVERIFY(model.data(model.index(2), FileChooserModel::IsImageRole).toBool());
        QVERIFY(!model.data(model.index(3), FileChooserModel::IsImageRole).toBool());
    }

    void filtersKeepFolders() {
        FileChooserModel model;
        model.setMimeFilters({QStringLiteral("image/*")});
        model.setFolder(home.filePath(QStringLiteral("Pictures")));
        QCOMPARE(names(model), QStringList({"Holiday", "anim.webp", "beach.png"}));
        model.setMimeFilters({QStringLiteral("image/png")});
        model.setNameFilters({QStringLiteral("*.webp")});
        QCOMPARE(names(model), QStringList({"Holiday", "anim.webp", "beach.png"}));
        model.setMimeFilters({});
        QCOMPARE(names(model), QStringList({"Holiday", "anim.webp"}));
    }

    void hiddenFilesOnRequest() {
        FileChooserModel model;
        model.setFolder(home.filePath(QStringLiteral("Pictures")));
        model.setShowHidden(true);
        QVERIFY(names(model).contains(QStringLiteral(".hidden.png")));
    }

    void foldersOnly() {
        FileChooserModel model;
        model.setDirectoriesOnly(true);
        model.setFolder(home.filePath(QStringLiteral("Pictures")));
        QCOMPARE(names(model), QStringList{QStringLiteral("Holiday")});
    }

    void searchLooksUnderTheFolder() {
        FileChooserModel model;
        model.setFolder(home.path());
        model.setSearch(QStringLiteral("SEA"));
        QCOMPARE(names(model), QStringList{QStringLiteral("sea.jpg")});
        QCOMPARE(model.data(model.index(0), FileChooserModel::PathRole).toString(),
                 home.filePath(QStringLiteral("Pictures/Holiday/sea.jpg")));
        model.setSearch(QString());
        QVERIFY(names(model).contains(QStringLiteral("Pictures")));
    }

    void recentIsNewestFirstAndRecentOnly() {
        FileChooserModel model;
        model.setRecent(true);
        const QStringList recent = names(model);
        QCOMPARE(recent.mid(0, 4), QStringList({"anim.webp", "report.pdf", "notes.txt", "beach.png"}));
        QVERIFY(!recent.contains(QStringLiteral("old.pdf")));
        QVERIFY(!recent.contains(QStringLiteral(".hidden.png")));
    }

    void placesAreTheMediaFolders() {
        const QVariantList places = FileChooserModel::places();
        QCOMPARE(places.first().toMap().value("path").toString(), home.path());
        bool pictures = false;
        for (const QVariant &place : places)
            pictures |= place.toMap().value("path").toString() == home.filePath(QStringLiteral("Pictures"));
        QVERIFY(pictures);
        QVERIFY(FileChooserModel::exists(home.filePath(QStringLiteral("Pictures/beach.png"))));
        QCOMPARE(FileChooserModel::join(home.path(), QStringLiteral("a.txt")), home.filePath(QStringLiteral("a.txt")));
    }
};

QTEST_GUILESS_MAIN(TestFileChooserModel)
#include "test_filechoosermodel.moc"
