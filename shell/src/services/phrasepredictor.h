#pragma once

#include <QHash>
#include <QObject>
#include <QStringList>
#include <qqml.h>

class PhrasePredictor : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    explicit PhrasePredictor(QObject *parent = nullptr);

    Q_INVOKABLE QStringList getPhrases(const QString &words) const;
    Q_INVOKABLE QString     getTopPhrase(const QString &words) const;

  private:
    QHash<QString, QStringList> m_phraseMap;
};
