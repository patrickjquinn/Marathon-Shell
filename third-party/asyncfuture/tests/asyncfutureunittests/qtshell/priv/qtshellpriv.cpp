#include <QRegularExpression>
#include <QtShell>
#include <QPair>
#include "qtshellpriv.h"

using namespace QtShell::Private;

QString QtShell::Private::normalize(const QString& path)
{
    QString p = path;
    if (p.count("/") == p.size()) {
        return "/";
    }

    p.remove(QRegularExpression("/*$"));
    return p;
}

QString QtShell::Private::canonicalPath(const QString &path)
{
    bool isWindow = false;
#ifdef Q_OS_WIN
    isWindow = true;
#endif
    return canonicalPath(path, isWindow);
}

QString QtShell::Private::canonicalPath(const QString &path, bool isWindow)
{
    QString p = path;

    p.replace(QRegularExpression("/+"),"/");

    QStringList token = p.split("/");

    QStringList res;

    for (int i = 0 ; i < token.size(); i++) {
        QString item = token[i];

        if (item == ".") {
            continue;
        } else if (item == "..") {
            if (res.size() > 0) {
                res.removeLast();
            }
        } else {
            res << item;
        }
    }

    if (!isWindow) {
        // Insert an empty string at the beginning. So it will add a "/" when it is calling "join()"
        if (res.size() > 0 &&
           !res[0].isEmpty() && res[0][0] != QChar(':')) {
            // "path begin with :/ is valid"
            res.insert(0, "");
        }
    } else {
        // No leading "/"
        while (res.size() && res[0].isEmpty()) {
            res.removeAt(0);
        }
    }

    return normalize(res.join("/"));
}


int QtShell::Private::bulk(const QString &source, const QString &target, std::function<bool (const QString &, const QString &, const QFileInfo &)> predicate)
{
    QString s = normalize(source);
    QString t = normalize(target);

    QString folder = QtShell::dirname(s);
    QString filter = QtShell::basename(s);

    QDir sourceDir(folder);
    QList<QFileInfo> files = sourceDir.entryInfoList(QStringList() << filter,
                                                     QDir::AllEntries | QDir::NoDot | QDir::NoDotDot);

    QFileInfo targetInfo(t);

    bool unexceptedError = false;

    if (files.size() > 1 && !targetInfo.isDir()) {
        return INVALID_TARGET;
    }

    if (files.size() == 0) {
        return NO_SUCH_FILE_OR_DIR;
    }

    foreach (QFileInfo file, files) {
        QString to = t;
        QString from = file.fileName();

        if (!folder.isEmpty()) {
            from = folder + "/" + from;
        }

        if (targetInfo.isDir()) {
            to = t + "/" + file.fileName();
        }

        unexceptedError = !predicate(from, to, file) || unexceptedError;
    }

    if (unexceptedError) {
        return UNEXCEPTED_ERROR;
    }

    return NO_ERROR;
}
