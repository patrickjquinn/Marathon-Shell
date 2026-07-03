#ifndef QTSHELL_H
#define QTSHELL_H

#include <QStringList>
#include <QPair>

namespace QtShell {

    QString dirname(const QString& path);

    QString basename(const QString& path);

    class FindOptions {
    public:
        FindOptions();

        int maxdepth;
    };

    QStringList find(const FindOptions& options, const QString& path, const QStringList& nameFilters = QStringList());

    QStringList find(const QString& path, const QStringList& nameFilters = QStringList());

    QStringList find(const QString& path, const QString& nameFilter);

    bool rmdir(const QString& path);

    bool touch(const QString &path);

    bool rm(const QString& file);

    bool rm(const QString& options,const QString& file);

    bool mkdir(const QString &path);

    bool mkdir(const QString &options, const QString &path);

    bool cp(const QString& source , const QString &target);

    bool cp(const QString& source , const QString &target, QList<QPair<QString,QString> > &log);

    bool cp(const QString& options, const QString& source , const QString &target);

    bool cp(const QString& options, const QString& source , const QString &target, QList<QPair<QString,QString> > &log);

    bool mv(const QString& source , const QString &target);

    bool mv(const QString& source , const QString &target, QList<QPair<QString,QString> > &log);

    QString pwd();

    QString cat(const QString& file);

    QString cat(const QStringList& files);

    // Implementation of `realpath -s`, return the canonicalised absolute pathname without resolving the symbolic link
    QString realpath_strip(const QString& input);

    QString realpath_strip(const QString& basePath, const QString& subPath);

    template <typename... Args>
    QString realpath_strip(const QString& basePath, const QString& subPath, Args... args) {
        return realpath_strip(realpath_strip(basePath, subPath), args...);
    }

    QString which(const QString& program);
}

#endif // QTSHELL_H
