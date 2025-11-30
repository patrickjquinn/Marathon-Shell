// Marathon Keyboard Input Method Engine - C++ Backend
// High-performance keyboard with zero-latency input processing
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

// Forward declarations
class PredictionEngine;
class DictionaryLoader;

/**
 * @brief High-performance Input Method Engine for Marathon Keyboard
 * 
 * This class handles all keyboard input with minimal latency by:
 * - Processing touch events directly in C++
 * - Running predictions on background thread
 * - Caching frequently used data
 * - Using lock-free data structures where possible
 */
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

    // Property getters
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

    // Property setters
    void setAutoCorrectEnabled(bool enabled);

    /**
     * @brief Process a key press with minimal latency
     * @param character The character to insert
     * @return true if processed successfully
     * 
     * This method is optimized for speed:
     * - Updates current word immediately
     * - Triggers async prediction update
     * - Returns in < 1ms
     */
    Q_INVOKABLE bool processKeyPress(const QString &character);

    /**
     * @brief Process backspace with word tracking
     */
    Q_INVOKABLE void processBackspace();

    /**
     * @brief Process space key (word completion)
     */
    Q_INVOKABLE void processSpace();

    /**
     * @brief Process enter key
     */
    Q_INVOKABLE void processEnter();

    /**
     * @brief Replace current word with prediction
     * @param word The predicted word to use
     */
    Q_INVOKABLE void acceptPrediction(const QString &word);

    /**
     * @brief Get alternate characters for long-press
     * @param character The base character
     * @return List of alternate characters
     */
    Q_INVOKABLE QStringList getAlternates(const QString &character) const;

    /**
     * @brief Learn a new word or increase frequency
     * @param word The word to learn
     */
    Q_INVOKABLE void learnWord(const QString &word);

    /**
     * @brief Clear current word state
     */
    Q_INVOKABLE void clearCurrentWord();

    /**
     * @brief Get performance metrics
     */
    Q_INVOKABLE QVariantMap getPerformanceMetrics() const;

  signals:
    void currentWordChanged();
    void predictionsChanged();
    void autoCorrectEnabledChanged();
    void averageLatencyChanged();

    /**
     * @brief Emitted when text should be committed to input field
     * @param text The text to commit
     * 
     * This is emitted AFTER visual feedback is shown,
     * ensuring perceived zero latency
     */
    void commitText(const QString &text);

    /**
     * @brief Emitted when backspace should be applied
     */
    void commitBackspace();

    /**
     * @brief Emitted when current word should be replaced
     * @param oldWord The word to replace
     * @param newWord The new word
     */
    void replaceWord(const QString &oldWord, const QString &newWord);

  private slots:
    void onPredictionsReady(const QStringList &predictions);

  private:
    void    updatePredictionsAsync();
    void    updateLatencyMetrics(qint64 latencyMs);
    QString applyAutoCorrect(const QString &word);

    // Current state
    QString     m_currentWord;
    QStringList m_predictions;
    bool        m_autoCorrectEnabled;

    // Performance tracking
    int           m_averageLatency;
    QList<qint64> m_latencySamples;
    QElapsedTimer m_latencyTimer;

    // Background processing
    QThread          *m_predictionThread;
    PredictionEngine *m_predictionEngine;
    DictionaryLoader *m_dictionaryLoader;

    // Thread safety
    mutable QMutex m_mutex;

    // Caches for performance
    QHash<QString, QStringList> m_alternatesCache;
    QHash<QString, QString>     m_autoCorrectCache;
};

/**
 * @brief Background prediction engine
 * 
 * Runs on separate thread to avoid blocking UI
 */
class PredictionEngine : public QObject {
    Q_OBJECT

  public:
    explicit PredictionEngine(QObject *parent = nullptr);

  public slots:
    void generatePredictions(const QString &prefix);

  signals:
    void predictionsReady(const QStringList &predictions);

  private:
    // Trie or similar fast structure for predictions
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

/**
 * @brief Async dictionary loader
 * 
 * Loads and indexes dictionary in background
 */
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

#endif // MARATHONKEYBOARDIME_H
