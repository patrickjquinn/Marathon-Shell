// Marathon Keyboard Input Method Engine - Implementation
#include "marathonkeyboardime.h"
#include <QDebug>
#include <QFile>
#include <QTextStream>
#include <QStandardPaths>
#include <algorithm>

// ========== MarathonKeyboardIME Implementation ==========

MarathonKeyboardIME::MarathonKeyboardIME(QObject *parent)
    : QObject(parent)
    , m_autoCorrectEnabled(true)
    , m_averageLatency(0)
    , m_predictionThread(new QThread(this))
    , m_predictionEngine(new PredictionEngine())
    , m_dictionaryLoader(new DictionaryLoader()) {
    // Move prediction engine to background thread
    m_predictionEngine->moveToThread(m_predictionThread);
    m_dictionaryLoader->moveToThread(m_predictionThread);

    // Connect signals
    connect(m_predictionEngine, &PredictionEngine::predictionsReady, this,
            &MarathonKeyboardIME::onPredictionsReady);

    // Start background thread
    m_predictionThread->start();

    // Load dictionary asynchronously
    QMetaObject::invokeMethod(m_dictionaryLoader, "loadDictionary", Qt::QueuedConnection);

    qDebug() << "[MarathonKeyboardIME] Initialized with background prediction engine";
}

MarathonKeyboardIME::~MarathonKeyboardIME() {
    m_predictionThread->quit();
    m_predictionThread->wait();

    delete m_predictionEngine;
    delete m_dictionaryLoader;
}

void MarathonKeyboardIME::setAutoCorrectEnabled(bool enabled) {
    if (m_autoCorrectEnabled != enabled) {
        m_autoCorrectEnabled = enabled;
        emit autoCorrectEnabledChanged();
    }
}

bool MarathonKeyboardIME::processKeyPress(const QString &character) {
    // Start latency timer
    m_latencyTimer.start();

    // Update current word immediately (< 0.1ms)
    m_currentWord.append(character);
    emit currentWordChanged();

    // Commit text immediately for zero perceived latency
    emit commitText(character);

    // Trigger async prediction update
    updatePredictionsAsync();

    // Record latency
    qint64 latency = m_latencyTimer.elapsed();
    updateLatencyMetrics(latency);

    return true;
}

void MarathonKeyboardIME::processBackspace() {
    m_latencyTimer.start();

    if (!m_currentWord.isEmpty()) {
        m_currentWord.chop(1);
        emit currentWordChanged();

        // Update predictions if word still exists
        if (!m_currentWord.isEmpty()) {
            updatePredictionsAsync();
        } else {
            m_predictions.clear();
            emit predictionsChanged();
        }
    }

    emit   commitBackspace();

    qint64 latency = m_latencyTimer.elapsed();
    updateLatencyMetrics(latency);
}

void MarathonKeyboardIME::processSpace() {
    m_latencyTimer.start();

    if (!m_currentWord.isEmpty()) {
        // Apply auto-correct if enabled
        QString finalWord = m_currentWord;
        if (m_autoCorrectEnabled) {
            QString corrected = applyAutoCorrect(m_currentWord);
            if (corrected != m_currentWord) {
                // Replace current word with corrected version
                emit replaceWord(m_currentWord, corrected);
                finalWord = corrected;
            }
        }

        // Learn the word
        learnWord(finalWord);

        // Clear current word
        m_currentWord.clear();
        m_predictions.clear();
        emit currentWordChanged();
        emit predictionsChanged();
    }

    emit   commitText(" ");

    qint64 latency = m_latencyTimer.elapsed();
    updateLatencyMetrics(latency);
}

void MarathonKeyboardIME::processEnter() {
    if (!m_currentWord.isEmpty()) {
        learnWord(m_currentWord);
        m_currentWord.clear();
        m_predictions.clear();
        emit currentWordChanged();
        emit predictionsChanged();
    }

    emit commitText("\n");
}

void MarathonKeyboardIME::acceptPrediction(const QString &word) {
    if (m_currentWord.isEmpty()) {
        return;
    }

    // Replace current word with prediction
    emit replaceWord(m_currentWord, word);

    // Learn the accepted word
    learnWord(word);

    // Clear state
    m_currentWord.clear();
    m_predictions.clear();
    emit currentWordChanged();
    emit predictionsChanged();
}

QStringList MarathonKeyboardIME::getAlternates(const QString &character) const {
    if (character.isEmpty()) {
        return QStringList();
    }

    // Check cache first
    QChar   ch  = character.at(0).toLower();
    QString key = QString(ch);

    if (m_alternatesCache.contains(key)) {
        return m_alternatesCache.value(key);
    }

    // Return empty list if not found (alternates defined in QML for now)
    return QStringList();
}

void MarathonKeyboardIME::learnWord(const QString &word) {
    if (word.length() < 2) {
        return;
    }

    // Update frequency asynchronously
    QMetaObject::invokeMethod(
        m_dictionaryLoader, [this, word]() { m_dictionaryLoader->updateFrequency(word, 10); },
        Qt::QueuedConnection);
}

void MarathonKeyboardIME::clearCurrentWord() {
    m_currentWord.clear();
    m_predictions.clear();
    emit currentWordChanged();
    emit predictionsChanged();
}

QVariantMap MarathonKeyboardIME::getPerformanceMetrics() const {
    QVariantMap metrics;
    metrics["averageLatency"]   = m_averageLatency;
    metrics["currentWord"]      = m_currentWord;
    metrics["predictionsCount"] = m_predictions.size();
    return metrics;
}

void MarathonKeyboardIME::onPredictionsReady(const QStringList &predictions) {
    m_predictions = predictions;
    emit predictionsChanged();
}

void MarathonKeyboardIME::updatePredictionsAsync() {
    if (m_currentWord.isEmpty()) {
        return;
    }

    // Trigger prediction generation on background thread
    QMetaObject::invokeMethod(m_predictionEngine, "generatePredictions", Qt::QueuedConnection,
                              Q_ARG(QString, m_currentWord));
}

void MarathonKeyboardIME::updateLatencyMetrics(qint64 latencyMs) {
    m_latencySamples.append(latencyMs);

    // Keep only last 100 samples
    if (m_latencySamples.size() > 100) {
        m_latencySamples.removeFirst();
    }

    // Calculate average
    qint64 sum = 0;
    for (qint64 sample : m_latencySamples) {
        sum += sample;
    }

    int newAverage = static_cast<int>(sum / m_latencySamples.size());
    if (newAverage != m_averageLatency) {
        m_averageLatency = newAverage;
        emit averageLatencyChanged();

        if (m_averageLatency > 10) {
            qWarning() << "[MarathonKeyboardIME] High latency detected:" << m_averageLatency
                       << "ms";
        }
    }
}

QString MarathonKeyboardIME::applyAutoCorrect(const QString &word) {
    // Check cache first
    if (m_autoCorrectCache.contains(word.toLower())) {
        return m_autoCorrectCache.value(word.toLower());
    }

    // Common typos (defined in QML AutoCorrect for now)
    // Return word unchanged - QML layer handles this
    return word;
}

// ========== PredictionEngine Implementation ==========

PredictionEngine::PredictionEngine(QObject *parent)
    : QObject(parent)
    , m_root(new TrieNode()) {
    buildTrie();
}

void PredictionEngine::generatePredictions(const QString &prefix) {
    if (prefix.isEmpty()) {
        emit predictionsReady(QStringList());
        return;
    }

    // Search trie for predictions
    QStringList predictions = searchTrie(prefix.toLower(), 3);

    emit        predictionsReady(predictions);
}

void PredictionEngine::buildTrie() {
    // Build trie from common words
    // This is a placeholder - real implementation would load from file
    QStringList commonWords = {"the", "be", "to",   "of",  "and", "a",    "in",   "that", "have",
                               "I",   "it", "for",  "not", "on",  "with", "he",   "as",   "you",
                               "do",  "at", "this", "but", "his", "by",   "from", "they"};

    for (const QString &word : commonWords) {
        TrieNode *current = m_root;
        for (const QChar &ch : word) {
            if (!current->children.contains(ch)) {
                current->children[ch]            = new TrieNode();
                current->children[ch]->character = ch;
            }
            current = current->children[ch];
        }
        current->isWord    = true;
        current->frequency = 100; // Default frequency
    }
}

QStringList PredictionEngine::searchTrie(const QString &prefix, int maxResults) {
    QStringList results;

    // Navigate to prefix node
    TrieNode *current = m_root;
    for (const QChar &ch : prefix) {
        if (!current->children.contains(ch)) {
            return results; // Prefix not found
        }
        current = current->children[ch];
    }

    // DFS to find words (simplified - real implementation would use priority queue)
    // For now, just return if current is a word
    if (current->isWord) {
        results.append(prefix);
    }

    return results;
}

// ========== DictionaryLoader Implementation ==========

DictionaryLoader::DictionaryLoader(QObject *parent)
    : QObject(parent) {}

void DictionaryLoader::loadDictionary() {
    qDebug() << "[DictionaryLoader] Loading dictionary...";

    // Load common words with frequencies
    // This is a placeholder - real implementation would load from file
    QStringList  commonWords = {"the", "be", "to",  "of",  "and", "a",    "in", "that", "have",
                                "I",   "it", "for", "not", "on",  "with", "he", "as",   "you"};

    QMutexLocker locker(&m_mutex);
    for (int i = 0; i < commonWords.size(); ++i) {
        m_wordFrequencies[commonWords[i]] = 1000 - (i * 10);
        emit loadProgress((i + 1) * 100 / commonWords.size());
    }

    qDebug() << "[DictionaryLoader] Loaded" << m_wordFrequencies.size() << "words";
    emit dictionaryLoaded();
}

bool DictionaryLoader::hasWord(const QString &word) const {
    QMutexLocker locker(&m_mutex);
    return m_wordFrequencies.contains(word.toLower());
}

int DictionaryLoader::getFrequency(const QString &word) const {
    QMutexLocker locker(&m_mutex);
    return m_wordFrequencies.value(word.toLower(), 0);
}

void DictionaryLoader::updateFrequency(const QString &word, int delta) {
    QMutexLocker locker(&m_mutex);
    QString      lowerWord       = word.toLower();
    m_wordFrequencies[lowerWord] = m_wordFrequencies.value(lowerWord, 0) + delta;
}
