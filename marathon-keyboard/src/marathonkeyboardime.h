

#ifndef MARATHONKEYBOARDIME_H
#define MARATHONKEYBOARDIME_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QHash>
#include <QThread>
#include <QMutex>
#include <QElapsedTimer>
#include <QPointF>
#include <QVariant>
#include <QVariantMap>

class PredictionEngine;
class DictionaryLoader;

class MarathonKeyboardIME : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentWord READ currentWord NOTIFY currentWordChanged)
    Q_PROPERTY(QStringList predictions READ predictions NOTIFY predictionsChanged)
    Q_PROPERTY(bool autoCorrectEnabled READ autoCorrectEnabled WRITE setAutoCorrectEnabled NOTIFY
                   autoCorrectEnabledChanged)
    Q_PROPERTY(int averageLatency READ averageLatency NOTIFY averageLatencyChanged)

  public:
    explicit MarathonKeyboardIME(QObject *parent = nullptr);
    ~MarathonKeyboardIME();

    QString currentWord() const {
        return m_currentWord;
    }
    QStringList predictions() const {
        return m_predictions;
    }
    bool autoCorrectEnabled() const {
        return m_autoCorrectEnabled;
    }
    int averageLatency() const {
        return m_averageLatency;
    }

    void                    setAutoCorrectEnabled(bool enabled);

    Q_INVOKABLE bool        processKeyPress(const QString &character);

    Q_INVOKABLE void        processBackspace();

    Q_INVOKABLE void        processSpace();

    Q_INVOKABLE void        processEnter();

    Q_INVOKABLE void        acceptPrediction(const QString &word);

    Q_INVOKABLE QStringList getAlternates(const QString &character) const;

    Q_INVOKABLE void        learnWord(const QString &word);

    Q_INVOKABLE void        clearCurrentWord();

    Q_INVOKABLE QVariantMap getPerformanceMetrics() const;

  signals:
    void currentWordChanged();
    void predictionsChanged();
    void autoCorrectEnabledChanged();
    void averageLatencyChanged();

    void commitText(const QString &text);

    void commitBackspace();

    void replaceWord(const QString &oldWord, const QString &newWord);

  private slots:
    void onPredictionsReady(const QStringList &predictions);

  private:
    void                        updatePredictionsAsync();
    void                        updateLatencyMetrics(qint64 latencyMs);
    QString                     applyAutoCorrect(const QString &word);

    QString                     m_currentWord;
    QStringList                 m_predictions;
    bool                        m_autoCorrectEnabled;

    int                         m_averageLatency;
    QList<qint64>               m_latencySamples;
    QElapsedTimer               m_latencyTimer;

    QThread                    *m_predictionThread;
    PredictionEngine           *m_predictionEngine;
    DictionaryLoader           *m_dictionaryLoader;

    mutable QMutex              m_mutex;

    QHash<QString, QStringList> m_alternatesCache;
    QHash<QString, QString>     m_autoCorrectCache;
};

class PredictionEngine : public QObject {
    Q_OBJECT

  public:
    explicit PredictionEngine(QObject *parent = nullptr);

  public slots:
    void generatePredictions(const QString &prefix);

  signals:
    void predictionsReady(const QStringList &predictions);

  private:
    struct TrieNode {
        QChar                    character;
        int                      frequency;
        bool                     isWord;
        QHash<QChar, TrieNode *> children;

        TrieNode()
            : frequency(0)
            , isWord(false) {}
        ~TrieNode() {
            qDeleteAll(children);
        }
    };

    TrieNode   *m_root;

    void        buildTrie();
    QStringList searchTrie(const QString &prefix, int maxResults = 3);
};

class DictionaryLoader : public QObject {
    Q_OBJECT

  public:
    explicit DictionaryLoader(QObject *parent = nullptr);

    Q_INVOKABLE void loadDictionary();
    Q_INVOKABLE bool hasWord(const QString &word) const;
    Q_INVOKABLE int  getFrequency(const QString &word) const;
    Q_INVOKABLE void updateFrequency(const QString &word, int delta = 1);

  signals:
    void dictionaryLoaded();
    void loadProgress(int percent);

  private:
    QHash<QString, int> m_wordFrequencies;
    mutable QMutex      m_mutex;
};

#endif
