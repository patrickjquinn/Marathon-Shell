#ifndef DESKTOPFILEPARSER_H
#define DESKTOPFILEPARSER_H

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QVariantList>

class DesktopFileParser : public QObject {
    Q_OBJECT

  public:
    explicit DesktopFileParser(QObject *parent = nullptr);

    Q_INVOKABLE QVariantList scanApplications(const QStringList &searchPaths);
    Q_INVOKABLE QVariantList scanApplications(const QStringList &searchPaths,
                                              bool               filterMobileFriendly);
    Q_INVOKABLE QVariantMap  parseDesktopFile(const QString &filePath);
    Q_INVOKABLE QString      resolveIconPath(const QString &iconName);

  private:
    QString     cleanExecLine(const QString &exec);
    QStringList findIconPaths(const QString &iconName);
    bool        isMobileFriendly(const QVariantMap &app);
};

#endif // DESKTOPFILEPARSER_H
