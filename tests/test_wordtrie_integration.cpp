#include "../shell/qml/keyboard/Data/WordTrie.h"
#include <QFile>
#include <QTextStream>
#include <QtTest/QtTest>

class TestWordTrieIntegration : public QObject {
    Q_OBJECT

  private slots:
    void testLoadFromDictionaryFile();
    void testRealWorldCompletions();
};

void TestWordTrieIntegration::testLoadFromDictionaryFile() {
    WordTrie    trie;

    QStringList dictionaryPaths;
    dictionaryPaths << "/usr/share/hunspell/en_US.dic"
                    << "/usr/share/myspell/dicts/en_US.dic";

    QString dicPath;
    for (const QString &path : dictionaryPaths) {
        if (QFile::exists(path)) {
            dicPath = path;
            break;
        }
    }

    if (dicPath.isEmpty()) {
        QSKIP("No en_US dictionary found, skipping integration test");
    }

    QFile file(dicPath);
    QVERIFY(file.open(QIODevice::ReadOnly | QIODevice::Text));

    QTextStream stream(&file);
    QString     firstLine = stream.readLine();

    int         loadedCount = 0;
    const int   MAX_WORDS   = 1000;

    while (!stream.atEnd() && loadedCount < MAX_WORDS) {
        QString line = stream.readLine().trimmed();
        if (line.isEmpty())
            continue;

        int     slashPos = line.indexOf('/');
        QString baseWord = (slashPos >= 0) ? line.left(slashPos) : line;

        if (baseWord.length() >= 3 && baseWord.length() <= 20) {
            trie.insert(baseWord);
            loadedCount++;
        }
    }

    QVERIFY(loadedCount > 100);
    QVERIFY(trie.size() >= 900);
    QVERIFY(trie.size() <= loadedCount);
}

void TestWordTrieIntegration::testRealWorldCompletions() {
    WordTrie trie;
    trie.insert("hello");
    trie.insert("help");
    trie.insert("helicopter");
    trie.insert("world");
    trie.insert("wonder");
    trie.insert("wonderful");

    QStringList helResults = trie.getCompletions("hel", 10);
    QVERIFY(helResults.size() >= 3);
    QVERIFY(helResults.contains("hello"));

    QStringList woResults = trie.getCompletions("wo", 10);
    QVERIFY(woResults.size() >= 3);
    QVERIFY(woResults.contains("world"));
    QVERIFY(woResults.contains("wonder"));
}

QTEST_MAIN(TestWordTrieIntegration)
#include "test_wordtrie_integration.moc"
