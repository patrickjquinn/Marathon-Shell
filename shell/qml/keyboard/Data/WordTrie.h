#ifndef MARATHON_WORDTRIE_H
#define MARATHON_WORDTRIE_H

#include <QStringList>
#include <QString>
#include <memory>
#include <unordered_map>

class WordTrie {
  public:
    WordTrie();
    ~WordTrie();

    void        insert(const QString &word);
    QStringList getCompletions(const QString &prefix, int maxResults = 10) const;
    void        clear();
    int         size() const {
        return m_wordCount;
    }

  private:
    struct Node {
        std::unordered_map<QChar, std::unique_ptr<Node>> children;
        bool                                             isWordEnd = false;
    };

    std::unique_ptr<Node> m_root;
    int                   m_wordCount = 0;

    void collectWords(const Node *node, const QString &prefix, QStringList &results,
                      int maxResults) const;
};

#endif
