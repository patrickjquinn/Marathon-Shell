#include "autocorrect.h"

#include <algorithm>
#include <QVector>

#include "dictionary.h"

AutoCorrect::AutoCorrect(Dictionary *dictionary, QObject *parent)
    : QObject(parent)
    , m_dictionary(dictionary)
    , m_commonTypos({
          {"teh", "the"},
          {"adn", "and"},
          {"youre", "you're"},
          {"dont", "don't"},
          {"cant", "can't"},
          {"wont", "won't"},
          {"didnt", "didn't"},
          {"doesnt", "doesn't"},
          {"hasnt", "hasn't"},
          {"havent", "haven't"},
          {"isnt", "isn't"},
          {"wasnt", "wasn't"},
          {"werent", "weren't"},
          {"shouldnt", "shouldn't"},
          {"wouldnt", "wouldn't"},
          {"couldnt", "couldn't"},
          {"thats", "that's"},
          {"whats", "what's"},
          {"hes", "he's"},
          {"shes", "she's"},
          {"its", "it's"},
          {"im", "I'm"},
          {"youve", "you've"},
          {"theyve", "they've"},
          {"weve", "we've"},
          {"ive", "I've"},
          {"recieve", "receive"},
          {"beleive", "believe"},
          {"neccessary", "necessary"},
          {"seperate", "separate"},
          {"definately", "definitely"},
          {"occured", "occurred"},
          {"begining", "beginning"},
          {"tommorrow", "tomorrow"},
          {"untill", "until"},
          {"alot", "a lot"},
      }) {}

void AutoCorrect::setEnabled(bool enabled) {
    if (m_enabled == enabled) {
        return;
    }
    m_enabled = enabled;
    emit enabledChanged();
}

QString AutoCorrect::correct(const QString &word) {
    if (!m_enabled || word.isEmpty()) {
        return word;
    }

    const QString lowerWord = word.toLower();
    const auto    typoIt    = m_commonTypos.constFind(lowerWord);
    if (typoIt != m_commonTypos.constEnd()) {
        return typoIt.value();
    }

    if (!m_dictionary || m_dictionary->hasWord(lowerWord)) {
        return word;
    }

    const QStringList suggestions = m_dictionary->predict(lowerWord);
    if (suggestions.isEmpty()) {
        return word;
    }

    const QString bestMatch = suggestions.first();
    const int     distance  = levenshteinDistance(lowerWord, bestMatch.toLower());
    if (distance <= 2) {
        return bestMatch;
    }
    return word;
}

QString AutoCorrect::shouldCorrect(const QString &word) {
    if (!m_enabled || word.size() < 3) {
        return {};
    }
    const QString corrected = correct(word);
    if (corrected != word) {
        return corrected;
    }
    return {};
}

void AutoCorrect::learnCorrection(const QString &typo, const QString &correction) {
    if (typo.isEmpty() || correction.isEmpty()) {
        return;
    }
    m_commonTypos.insert(typo.toLower(), correction);
}

int AutoCorrect::levenshteinDistance(const QString &first, const QString &second) const {
    if (first.isEmpty()) {
        return second.size();
    }
    if (second.isEmpty()) {
        return first.size();
    }

    const int    rows = second.size() + 1;
    const int    cols = first.size() + 1;
    QVector<int> previous(cols);
    QVector<int> current(cols);

    for (int col = 0; col < cols; ++col) {
        previous[col] = col;
    }

    for (int row = 1; row < rows; ++row) {
        current[0] = row;
        for (int col = 1; col < cols; ++col) {
            const bool same      = second.at(row - 1) == first.at(col - 1);
            const int  cost      = same ? 0 : 1;
            const int  insertion = current[col - 1] + 1;
            const int  deletion  = previous[col] + 1;
            const int  replace   = previous[col - 1] + cost;
            current[col]         = std::min({insertion, deletion, replace});
        }
        std::swap(current, previous);
    }
    return previous[cols - 1];
}
