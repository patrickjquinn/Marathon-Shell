#include "WordTrie.h"
#include <utility>   // std::as_const

WordTrie::WordTrie()
    : m_root(std::make_unique<Node>())
    , m_wordCount(0) {}

WordTrie::~WordTrie() = default;

void WordTrie::insert(const QString &word) {
    if (word.isEmpty())
        return;

    Node *current = m_root.get();
    const auto lowered = word.toLower();
    for (const QChar &ch : lowered) {
        if (current->children.find(ch) == current->children.end()) {
            current->children[ch] = std::make_unique<Node>();
        }
        current = current->children[ch].get();
    }

    if (!current->isWordEnd) {
        current->isWordEnd = true;
        m_wordCount++;
    }
}

QStringList WordTrie::getCompletions(const QString &prefix, int maxResults) const {
    if (prefix.isEmpty() || maxResults <= 0)
        return QStringList();

    QStringList results;
    Node       *current     = m_root.get();
    QString     lowerPrefix = prefix.toLower();

    for (const QChar &ch : std::as_const(lowerPrefix)) {
        auto it = current->children.find(ch);
        if (it == current->children.end()) {
            return results;
        }
        current = it->second.get();
    }

    if (current->isWordEnd) {
        results.append(lowerPrefix);
    }

    collectWords(current, lowerPrefix, results, maxResults);
    return results;
}

void WordTrie::collectWords(const Node *node, const QString &prefix, QStringList &results,
                            int maxResults) const {
    if (results.size() >= maxResults)
        return;

    for (const auto &[ch, child] : node->children) {
        QString newPrefix = prefix + ch;
        if (child->isWordEnd && results.size() < maxResults) {
            results.append(newPrefix);
        }
        if (results.size() < maxResults) {
            collectWords(child.get(), newPrefix, results, maxResults);
        }
    }
}

void WordTrie::clear() {
    m_root      = std::make_unique<Node>();
    m_wordCount = 0;
}
