#include "dictionary.h"

#include "emojipredictor.h"
#include "phrasepredictor.h"
#include "qml/keyboard/Data/WordEngine.h"

Dictionary::Dictionary(WordEngine *wordEngine, EmojiPredictor *emojiPredictor,
                       PhrasePredictor *phrasePredictor, QObject *parent)
    : QObject(parent)
    , m_wordEngine(wordEngine)
    , m_emojiPredictor(emojiPredictor)
    , m_phrasePredictor(phrasePredictor) {
    if (m_wordEngine) {
        connect(m_wordEngine, &WordEngine::predictionsReady, this, &Dictionary::onPredictionsReady);
    }
}

// Enable WordEngine on first use. WordEngine ships with enabled=false to
// keep the hunspell English dictionary (~15-20 MB resident) out of the
// shell's idle heap. The first predict/hasWord/learnWord call flips the
// flag and queues the actual dict load on WordEngine's worker thread.
void Dictionary::ensureWordEngineReady() {
    if (m_wordEngine && !m_wordEngine->enabled()) {
        m_wordEngine->setEnabled(true);
    }
}

QStringList Dictionary::predict(const QString &prefix) {
    if (prefix.isEmpty()) {
        return {};
    }
    if (!m_wordEngine) {
        return {};
    }
    ensureWordEngineReady();
    if (!m_wordEngine->enabled()) {
        return {};
    }
    if (m_lastPredictionPrefix != prefix) {
        setLastPredictionPrefix(prefix);
        setCachedPredictions({});
        m_wordEngine->requestPredictions(prefix, 5);
    }
    return m_cachedPredictions;
}

QString Dictionary::getEmojiForWord(const QString &word) const {
    if (!m_emojiPredictor || word.isEmpty()) {
        return {};
    }
    return m_emojiPredictor->getTopEmoji(word);
}

QStringList Dictionary::getPhraseCompletions(const QString &context) const {
    if (!m_phrasePredictor || context.isEmpty()) {
        return {};
    }
    return m_phrasePredictor->getPhrases(context);
}

void Dictionary::learnWord(const QString &word) {
    if (!m_wordEngine) {
        return;
    }
    ensureWordEngineReady();
    if (!m_wordEngine->enabled()) {
        return;
    }
    if (word.size() < 2) {
        return;
    }
    m_wordEngine->learnWord(word);
}

bool Dictionary::hasWord(const QString &word) const {
    if (!m_wordEngine || word.isEmpty()) {
        return false;
    }
    // const_cast: ensureWordEngineReady toggles a member. The intent is
    // still semantically const for the caller (whether or not we know
    // about a word).
    const_cast<Dictionary *>(this)->ensureWordEngineReady();
    if (!m_wordEngine->enabled()) {
        return false;
    }
    return m_wordEngine->hasWord(word);
}

void Dictionary::setCachedPredictions(const QStringList &predictions) {
    if (m_cachedPredictions == predictions) {
        return;
    }
    m_cachedPredictions = predictions;
    emit cachedPredictionsChanged();
}

void Dictionary::setLastPredictionPrefix(const QString &prefix) {
    if (m_lastPredictionPrefix == prefix) {
        return;
    }
    m_lastPredictionPrefix = prefix;
    emit lastPredictionPrefixChanged();
}

void Dictionary::onPredictionsReady(const QString &prefix, const QStringList &predictions) {
    if (prefix != m_lastPredictionPrefix) {
        return;
    }
    QStringList   enhanced = predictions;
    const QString emoji    = getEmojiForWord(prefix);
    if (!emoji.isEmpty() && enhanced.size() < 5 && !enhanced.contains(emoji)) {
        enhanced.append(emoji);
    }
    setCachedPredictions(enhanced);
}
