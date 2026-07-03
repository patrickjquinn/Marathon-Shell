#ifndef QTSHELLPRIV_H
#define QTSHELLPRIV_H

#include <QDir>
#include <QString>
#include <QtCore>
#include <functional>

namespace QtShell {

    namespace Private {

        /// Remove trailing "/" from a path.
        QString normalize(const QString& path);

        /// Returns the canonical path including the file name, i.e. an absolute path without redundant "." or ".." elements and double "/"
        /// The input must be an absolute path
        QString canonicalPath(const QString& path);

        QString canonicalPath(const QString& path, bool isWindow);

        typedef enum {
            NO_ERROR = 0,
            INVALID_TARGET = -1,
            NO_SUCH_FILE_OR_DIR = -2,
            UNEXCEPTED_ERROR = -3
        } BulkError ;

        int bulk(const QString& source, const QString& target, std::function<bool(const QString&, const QString&, const QFileInfo&) > predicate);
    }
}

#endif // QTSHELLPRIV_H
