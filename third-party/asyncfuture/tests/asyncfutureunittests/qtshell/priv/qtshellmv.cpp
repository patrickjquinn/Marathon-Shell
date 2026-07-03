#include "qtshell.h"
#include "priv/qtshellpriv.h"

using namespace QtShell::Private;

static bool _mv(const QString &source, const QString &target, QList<QPair<QString,QString> > &log) {
    if (source.isEmpty() || target.isEmpty()) {
        qWarning() << "usage: mv(source, target)";
        return false;
    }

    return QtShell::Private::bulk(source, target, [&](const QString& from , const QString& to, const QFileInfo& fromInfo){
        Q_UNUSED(fromInfo);

        QDir dir;
        log << QPair<QString,QString>(from, to);
        return dir.rename(from, to);
    });
}

bool QtShell::mv(const QString &source, const QString &target) {
    QList<QPair<QString,QString> > log;
    return _mv(source, target, log) == NO_ERROR;
}

bool QtShell::mv(const QString &source, const QString &target, QList<QPair<QString,QString> > &log) {
    return _mv(source, target, log) == NO_ERROR;
}
