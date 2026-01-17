#pragma once

#include <QObject>
#include <QStringList>
#include <qqml.h>

class WordEngine;
class EmojiPredictor;
class PhrasePredictor;

class Dictionary : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QStringList cachedPredictions READ cachedPredictions NOTIFY cachedPredictionsChanged)
    Q_PROPERTY(
        QString lastPredictionPrefix READ lastPredictionPrefix NOTIFY lastPredictionPrefixChanged)

  public:
    explicit Dictionary(WordEngine *wordEngine, EmojiPredictor *emojiPredictor,
                        PhrasePredictor *phrasePredictor, QObject *parent = nullptr);

    QStringList cachedPredictions() const {
        return m_cachedPredictions;
    }
    QString lastPredictionPrefix() const {
        return m_lastPredictionPrefix;
    }

    Q_INVOKABLE QStringList predict(const QString &prefix);
    Q_INVOKABLE QString     getEmojiForWord(const QString &word) const;
    Q_INVOKABLE QStringList getPhraseCompletions(const QString &context) const;
    Q_INVOKABLE void        learnWord(const QString &word);
    Q_INVOKABLE bool        hasWord(const QString &word) const;

  signals:
    void cachedPredictionsChanged();
    void lastPredictionPrefixChanged();

  private:
    void             setCachedPredictions(const QStringList &predictions);
    void             setLastPredictionPrefix(const QString &prefix);
    void             onPredictionsReady(const QString &prefix, const QStringList &predictions);

    WordEngine      *m_wordEngine;
    EmojiPredictor  *m_emojiPredictor;
    PhrasePredictor *m_phrasePredictor;
    QStringList      m_cachedPredictions;
    QString          m_lastPredictionPrefix;
};
