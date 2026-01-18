#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <qqml.h>

class EmojiPredictor : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    explicit EmojiPredictor(QObject *parent = nullptr);

    Q_INVOKABLE QStringList getEmojis(const QString &word) const;
    Q_INVOKABLE QString     getTopEmoji(const QString &word) const;

  private:
    QHash<QString, QStringList> m_emojiMap;
};
