#pragma once

class QQmlEngine;
class QJSEngine;

#include <QHash>
#include <QObject>
#include <QStringList>
#include <qqml.h>

class EmojiPredictor : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
  public:
    // QML_SINGLETON factory — required so the type registers correctly in
    // marathon-app-runner processes that import this module without the
    // shell's explicit qmlRegisterSingletonInstance call. Shell process
    // still calls qmlRegisterSingletonInstance in main.cpp; that override
    // wins so shell-side C++ consumers share the same instance pointer.
    static EmojiPredictor *create(QQmlEngine *, QJSEngine *);

  public:
    explicit EmojiPredictor(QObject *parent = nullptr);

    Q_INVOKABLE QStringList getEmojis(const QString &word) const;
    Q_INVOKABLE QString     getTopEmoji(const QString &word) const;

  private:
    QHash<QString, QStringList> m_emojiMap;
};
