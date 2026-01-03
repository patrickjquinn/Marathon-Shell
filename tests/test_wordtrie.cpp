#include "../shell/qml/keyboard/Data/WordTrie.h"
#include <QtTest/QtTest>

class TestWordTrie : public QObject {
    Q_OBJECT

  private slots:
    void testInsertAndSize();
    void testGetCompletionsBasic();
    void testGetCompletionsMaxResults();
    void testGetCompletionsCaseInsensitive();
    void testGetCompletionsNoMatch();
    void testGetCompletionsEmptyPrefix();
    void testClear();
};

void TestWordTrie::testInsertAndSize() {
    WordTrie trie;
    QCOMPARE(trie.size(), 0);

    trie.insert("hello");
    QCOMPARE(trie.size(), 1);

    trie.insert("hello");
    QCOMPARE(trie.size(), 1);

    trie.insert("world");
    QCOMPARE(trie.size(), 2);
}

void TestWordTrie::testGetCompletionsBasic() {
    WordTrie trie;
    trie.insert("hello");
    trie.insert("help");
    trie.insert("helicopter");
    trie.insert("world");

    QStringList results = trie.getCompletions("hel", 10);

    QVERIFY(results.contains("hello"));
    QVERIFY(results.contains("help"));
    QVERIFY(results.contains("helicopter"));
    QVERIFY(!results.contains("world"));
}

void TestWordTrie::testGetCompletionsMaxResults() {
    WordTrie trie;
    trie.insert("test1");
    trie.insert("test2");
    trie.insert("test3");
    trie.insert("test4");

    QStringList results = trie.getCompletions("test", 2);

    QCOMPARE(results.size(), 2);
}

void TestWordTrie::testGetCompletionsCaseInsensitive() {
    WordTrie trie;
    trie.insert("Hello");
    trie.insert("WORLD");

    QStringList results1 = trie.getCompletions("hel", 10);
    QVERIFY(results1.contains("hello"));

    QStringList results2 = trie.getCompletions("WOR", 10);
    QVERIFY(results2.contains("world"));
}

void TestWordTrie::testGetCompletionsNoMatch() {
    WordTrie trie;
    trie.insert("hello");

    QStringList results = trie.getCompletions("xyz", 10);
    QCOMPARE(results.size(), 0);
}

void TestWordTrie::testGetCompletionsEmptyPrefix() {
    WordTrie trie;
    trie.insert("hello");

    QStringList results = trie.getCompletions("", 10);
    QCOMPARE(results.size(), 0);
}

void TestWordTrie::testClear() {
    WordTrie trie;
    trie.insert("hello");
    trie.insert("world");
    QCOMPARE(trie.size(), 2);

    trie.clear();
    QCOMPARE(trie.size(), 0);

    QStringList results = trie.getCompletions("hel", 10);
    QCOMPARE(results.size(), 0);
}

QTEST_MAIN(TestWordTrie)
#include "test_wordtrie.moc"
