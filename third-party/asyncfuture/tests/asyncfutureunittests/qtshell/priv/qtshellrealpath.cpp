#include "qtshell.h"
#include "priv/qtshellpriv.h"

using namespace QtShell::Private;

QString QtShell::realpath_strip(const QString &file) {
    QString input = file;

    QUrl url(input);

    if (url.scheme() == "file") {
        input = url.path();

#ifdef Q_OS_WIN32
        // Handle network drive.
        if (!url.host().isEmpty()) { // It is a network drive
            input = "//" + url.host() + url.path();
            return input;
        }
#endif
    } else if (url.scheme() == "qrc") {
        input = QString(":") + url.path();
    }

#ifdef Q_OS_WIN32
    // For processing network path

    if (input.startsWith("\\\\") || input.startsWith("//")) {
        input.replace("\\", "/");
        return input;
    }

#endif

    QFileInfo info(input);

    if (info.isAbsolute()) { // It is not a I/O blocking call
        return canonicalPath(input);
    }

    return canonicalPath(info.absoluteFilePath());
}

QString QtShell::realpath_strip(const QString &basePath, const QString &subPath)
{
    QString res;
    QString p = realpath_strip(basePath); // No trailing "/"

    if (subPath.size() == 0) {
        return p;
    }

    if (subPath[0] == QChar('/')) {
        res = realpath_strip(basePath + subPath);
    } else {
        res = realpath_strip(basePath + "/" + subPath);
    }

    return res;
}
