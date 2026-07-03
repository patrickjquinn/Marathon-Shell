#include <QtCore>
#include <QDir>
#include <QQueue>
#include <QCommandLineParser>
#include "priv/qtshellpriv.h"

#ifdef WIN32
#include <sys/utime.h>
#else
#include <utime.h>
#endif

#include "qtshell.h"

using namespace QtShell::Private;

/// Take out "." and ".." files
static QStringList filterLocalFiles(const QStringList& files) {
    QStringList result;
    for (int i = 0 ; i < files.size() ; i++) {
        QString file = files[i];
        if (file == "." || file == "..") {
            continue;
        }
        result << file;
    }

    return result;
}

static QList<QFileInfo> filterLocalFiles(const QList<QFileInfo>& files) {
    QList<QFileInfo> result;
    for (int i = 0 ; i < files.size() ; i++) {
        QFileInfo file = files[i];
        if (file.fileName() == "." || file.fileName() == "..") {
            continue;
        }
        result << file;
    }

    return result;
}

static QStringList preservedPaths() {
    QStringList preservePaths;
    preservePaths << "/";

    for (int i = QStandardPaths::DesktopLocation ;
         i <= QStandardPaths::AppConfigLocation; i++) {
        QStringList paths =  QStandardPaths::standardLocations((QStandardPaths::StandardLocation) i);
        preservePaths.append(paths);
    }

    return preservePaths;
}


QStringList QtShell::find(const QtShell::FindOptions &options, const QString &root, const QStringList &nameFilters)
{
    QDir dir(realpath_strip(root));
    QString absRoot = dir.absolutePath();

    class QueueItem {
    public:
        QueueItem(QString path, int depth = 1) : path(path) , depth(depth) {
            depth = 1;
        }
        QString path;
        int depth;
    };

    QStringList result;

    auto resolve = [=](QString path) {
        return path.replace(absRoot, root);
    };

    auto match = [](const QString&fileName,const QStringList &nameFilters) {
        bool res = false;

        for (int i = 0 ; i < nameFilters.size() ; i++) {
            const QString& filter = nameFilters.at(i);
            QRegularExpression rx(QRegularExpression::wildcardToRegularExpression(filter));
            QRegularExpressionMatch match = rx.match(fileName);
            if (match.hasMatch()) {
                res = true;
                break;
            }
        }

        return res;
    };

    auto append = [&](const QString& absPath, const QString& fileName) {
        if (nameFilters.size() > 0 && !match(fileName, nameFilters)) {
            return;
        }

        result << resolve(absPath);
    };

    QQueue<QueueItem> queue;
    queue.enqueue(QueueItem(absRoot));
    append(absRoot, "");

    while (queue.size() > 0) {
        QueueItem current = queue.dequeue();
        QDir dir(current.path);
        QFileInfoList infos = dir.entryInfoList();

        if (options.maxdepth >=0 && current.depth > options.maxdepth) {
            continue;
        }

        for (int i = 0 ; i < infos.size() ; i++) {
            QFileInfo info = infos.at(i);

            if (info.fileName() == "." || info.fileName() == "..") {
                continue;
            }

            QString absPath = info.absoluteFilePath();

            if (info.isDir()) {
                queue.enqueue(QueueItem(absPath, current.depth + 1) );
                append(absPath, info.fileName());
                continue;
            }

            append(absPath, info.fileName());
        }
    }

    return result;
}


QStringList QtShell::find(const QString &root, const QStringList &nameFilters)
{
    FindOptions options;
    return find(options, root, nameFilters);
}

QString QtShell::dirname(const QString &input)
{
    // Don't use QFileInfo.absolutePath() since it return absolute path.
    // The behaviour is different than Unix's dirname command

    QString path = normalize(input);
    QStringList token = path.split("/");
    QString result = "/";

    if (token.size() == 1) {
        result = ".";
    } else {
        token.removeLast();
        result = token.join("/");
    }

    if (result.isEmpty()) {
        result = "/";
    }

    return result;
}

QString QtShell::basename(const QString &input)
{
    QString path = normalize(input);

    if (path == "/") {
        // Special case
        return "/";
    }

    QStringList token = path.split("/");

    if (path[path.size() - 1] == QChar('/')) {
        token.removeLast();
    }

    return token.last();
}

bool QtShell::rmdir(const QString &path)
{
    QDir dir(path);

    QStringList entry = filterLocalFiles(dir.entryList());
    if (entry.size() > 0) {
        qWarning() << QString("rmdir: %1: Directory not empty").arg(path);
        return false;
    }

    return dir.removeRecursively();
}

bool QtShell::touch(const QString &path)
{
    bool res = true;
    QFileInfo info(path);

    if (!info.exists()) {

        QFile file(path);
        if (!file.open(QIODevice::WriteOnly)) {
            qWarning() << "Failed to create file:" << path;
            res = false;
        }
        file.close();

    } else {
        QByteArray bytes = path.toUtf8();

        if (utime(bytes.constData(), 0) == -1) {
            qWarning() << "utimes failed:" << path;
            res = false;
        }
    }

    return res;
}

static bool _rm(const QString &file,
                 bool recursive = false,
                 bool verbose = false,
                 bool force = false)
{
    QString path = file;

    if (path.isEmpty()) {
        qWarning() << "rm: it do not accept empty argument";
        return false;
    }

    path = normalize(path);

    bool res = true;
    QString folder = QtShell::dirname(path);
    QString filter = QtShell::basename(path);

    QDir dir(folder);

    QStringList preservePaths = preservedPaths();

    QList<QFileInfo> files = dir.entryInfoList(QStringList() << filter);
    files = filterLocalFiles(files);

    if (files.size() == 0) {
        if (!force) {
            qWarning() << QString("rm: %1: No such file or directory").arg(filter);
            return false;
        }

        // If force is true, remove a non existed files is not a problem
        return true;
    }

    foreach (QFileInfo file, files) {
        if (preservePaths.indexOf(file.absoluteFilePath()) >= 0) {
            qWarning() << QString("rm: %1: is a preserved directory").arg(file.absoluteFilePath());
            continue;
        }
        if (file.isDir()) {

            if (!recursive) {
                qWarning() << QString("rm: %1: is a directory").arg(file.fileName());
                res = false;
            } else {
                QDir dir(file.absoluteFilePath());
                if (verbose) { qDebug().noquote() << file.absoluteFilePath();}
                if (!dir.removeRecursively()) {
                    res = false;
                    qWarning() << QString("rm: %1: can not remove the directory").arg(file.absoluteFilePath());
                }
            }
            continue;
        }

        if (verbose) { qDebug().noquote() << file.absoluteFilePath();}
        if (!QFile::remove(file.absoluteFilePath()) ) {
            qWarning() << QString("rm: %1: can not remove the file").arg(file.fileName());
            res = false;
        }
    }

    return res;
}

bool QtShell::rm(const QString &options, const QString &file)
{
    QCommandLineParser parser;
    parser.addOption(QCommandLineOption("v"));
    parser.addOption(QCommandLineOption("r"));
    parser.addOption(QCommandLineOption("R"));
    parser.addOption(QCommandLineOption("f")); // dummy

    if (!parser.parse(QStringList() << "rm" << options)) {
        qWarning() << QString("rm: %1").arg(parser.errorText());
        return false;
    }

    bool recursive = parser.isSet("r") || parser.isSet("R");
    bool verbose = parser.isSet("v");
    bool force = parser.isSet("f");

    return _rm(file, recursive, verbose, force);
}

bool QtShell::rm(const QString &file)
{
    return _rm(file);
}


bool QtShell::mkdir(const QString &path)
{
    QDir dir(path);

    if (dir.exists()) {
        qWarning() << QString("mkdir: %1: File exists").arg(path);
        return false;
    }

    QString folder = dirname(path);
    QString file = basename(path);
    dir = QDir(folder);

    return dir.mkdir(file);
}

bool QtShell::mkdir(const QString &options, const QString &path)
{
    QCommandLineParser parser;
    parser.addOption(QCommandLineOption("p"));

    if (!parser.parse(QStringList() << "mkdir" << options)) {
        qWarning() << QString("mkdir: %1").arg(parser.errorText());
        return false;
    }

    bool p = parser.isSet("p");

    if (!p) {
        return mkdir(path);
    }

    QDir dir;
    return dir.mkpath(path);
}

// The real cp function
static bool _cp(QString source,
                QString target,
                QList<QPair<QString,QString> > &log,
                bool recursive = false,
                bool verbose = false) {

    if (source.isEmpty() || target.isEmpty()) {
        qWarning() << "cp(const QString &source, const QString &target)";
        return false;
    }

    int code = bulk(source, target, [&](const QString& from , const QString& to, const QFileInfo& fromInfo) {
        bool res = true;

        if (fromInfo.isDir()) {
            if (!recursive) {
                qWarning() << QString("cp: %1 is a directory (not copied)").arg(from);
                res = false;
            } else {
                QtShell::mkdir(to);
                QDir nextDir(from);

                if (nextDir.entryList().size() > 2) { // except "." && ".."
                    res = _cp(from + "/*",
                              to, log, recursive, verbose);
                }
            }
            return res;
        }


        if (verbose) {
            qDebug().noquote() << QString("%1 -> %2").arg(from).arg(to);
        }

        if (QFile::exists(to)) {
            if (!QFile::remove(to)) {
                qWarning() << QString("cp: %1: Failed to overwrite to %2").arg(from).arg(to);
                return false;
            }
        }

        if (!QFile::copy(from, to)) {
            qWarning() << QString("cp: %1: Failed to copy to %2").arg(from).arg(to);
            res = false;
        }

        if (res) {
            log << QPair<QString,QString>(from, to);
        }

        return res;
    });

    switch (code) {
    case NO_SUCH_FILE_OR_DIR:
        qWarning() << QString("cp: %1: No such file or directory").arg(source);
        break;
    case INVALID_TARGET:
        qWarning() << QString("cp: %1 %2: Invalid target").arg(source).arg(target);
        break;
    }

    return code == NO_ERROR;
}

bool QtShell::cp(const QString &source, const QString &target)
{
    QList<QPair<QString, QString> > log;

    return _cp(source, target, log);
}

bool QtShell::cp(const QString &source, const QString &target, QList<QPair<QString, QString> > &log)
{
    return _cp(source, target, log);
}

bool QtShell::cp(const QString& options, const QString& source , const QString &target) {
    QList<QPair<QString, QString> > log;
    return cp(options, source, target, log);
}

bool QtShell::cp(const QString &options, const QString &source, const QString &target, QList<QPair<QString, QString> > &log)
{
    QCommandLineParser parser;
    parser.addOption(QCommandLineOption("v"));
    parser.addOption(QCommandLineOption("R"));
    parser.addOption(QCommandLineOption("a"));

    if (!parser.parse(QStringList() << "cp" << options)) {
        qWarning() << QString("cp: %1").arg(parser.errorText());
        return false;
    }

    bool recursive = parser.isSet("R") || parser.isSet("a");
    bool verbose = parser.isSet("v");

    return _cp(source, target, log, recursive, verbose);

}


QStringList QtShell::find(const QString &path, const QString &nameFilter)
{
    QStringList nameFilters;
    if (!nameFilter.isEmpty()) {
        nameFilters << nameFilter;
    }

    return find(path, nameFilters);
}

QString QtShell::pwd()
{
    return QDir::currentPath();
}

QString QtShell::cat(const QString &file)
{
    QString path = realpath_strip(file);

    QFileInfo info(path);

    if (!info.exists()) {
        qWarning() << QString("cat: %1: No such file or directory").arg(file);
        return "";
    }

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        qWarning() << QString("cat: %1: %2").arg(f.errorString()).arg(file);
        return "";
    }

    QByteArray content = f.readAll();

    return content;
}

QString QtShell::cat(const QStringList &files)
{
    QString content;

    for (int i = 0 ; i < files.size() ; i++) {
        if (i != 0) {
            content = content + "\n";
        }
        content = content + cat(files[i]);
    }

    return content;
}

QtShell::FindOptions::FindOptions()
{
    maxdepth = -1;
}

QString QtShell::which(const QString &program)
{
    auto path = qgetenv("PATH");
#ifdef Q_OS_WIN32
    auto separator = ';';
    auto exec = program + ".exe";
#else
    auto separator = ':';
    auto exec = program;
#endif

    auto paths = path.split(separator);
    QString res;

    for (auto& path: paths) {
        auto file = realpath_strip(path, exec);
        if (QFile::exists(file)) {
            res = QDir::toNativeSeparators(file);
            break;
        }
    }
    return res;
}
