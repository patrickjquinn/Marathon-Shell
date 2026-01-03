#include "qml/keyboard/Data/WordTrie.h"
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
    void testEmptyWord();
    void testVeryLongWord();
    void testSpecialCharacters();
    void testUnicode();
    void testDuplicates();
    void testMemoryStress();
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

void TestWordTrie::testEmptyWord() {
    WordTrie trie;
    trie.insert("");
    QCOMPARE(trie.size(), 0);
}

void TestWordTrie::testVeryLongWord() {
    WordTrie trie;
    QString  longWord(10000, 'a');
    trie.insert(longWord);
    QCOMPARE(trie.size(), 1);
    QStringList results = trie.getCompletions(longWord.left(100), 10);
    QVERIFY(results.contains(longWord));
}

void TestWordTrie::testSpecialCharacters() {
    WordTrie trie;
    trie.insert("hello-world");
    trie.insert("hello_world");
    trie.insert("hello.world");
    QCOMPARE(trie.size(), 3);
}

void TestWordTrie::testUnicode() {
    WordTrie trie;
    trie.insert("café");
    trie.insert("naïve");
    trie.insert("北京");
    QCOMPARE(trie.size(), 3);
    QStringList results = trie.getCompletions("caf", 10);
    QVERIFY(results.size() > 0);
}

void TestWordTrie::testDuplicates() {
    WordTrie trie;
    trie.insert("test");
    trie.insert("TEST");
    trie.insert("Test");
    QCOMPARE(trie.size(), 1);
    QStringList results = trie.getCompletions("te", 10);
    QCOMPARE(results.size(), 1);
}

void TestWordTrie::testMemoryStress() {
    for (int i = 0; i < 100; i++) {
        WordTrie *trie = new WordTrie();
        for (int j = 0; j < 1000; j++) {
            trie->insert(QString("word%1").arg(j));
        }
        delete trie;
    }
    QVERIFY(true);
}

QTEST_MAIN(TestWordTrie)
#include "test_wordtrie.moc"
