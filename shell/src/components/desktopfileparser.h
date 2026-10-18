#ifndef DESKTOPFILEPARSER_H
#define DESKTOPFILEPARSER_H

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QVariantList>
#include <QHash>

class DesktopFileParser : public QObject {
    Q_OBJECT

  public:
    explicit DesktopFileParser(QObject *parent = nullptr);

    Q_INVOKABLE QVariantList scanApplications(const QStringList &searchPaths);
    Q_INVOKABLE QVariantList scanApplications(const QStringList &searchPaths,
                                              bool               filterMobileFriendly);
    // includeHidden: also an entry that asks not to be shown (NoDisplay,
    // Hidden), which can still be launched by its id.
    Q_INVOKABLE QVariantMap  parseDesktopFile(const QString &filePath, bool includeHidden = false);
    Q_INVOKABLE QString      resolveIconPath(const QString &iconName);

  private:
    QString                 cleanExecLine(const QString &exec);
    QStringList             findIconPaths(const QString &iconName);
    bool                    isMobileFriendly(const QVariantMap &app);

    QHash<QString, QString> m_iconCache;
};

#endif
