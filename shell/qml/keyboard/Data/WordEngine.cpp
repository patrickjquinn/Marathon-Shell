#include "WordEngine.h"

#ifdef HAVE_HUNSPELL
#include <hunspell/hunspell.hxx>
#else
class Hunspell {
  public:
    Hunspell(const char *, const char *, const char * = nullptr)
        : encoding("UTF-8") {}
    int add_dic(const char *, const char * = nullptr) {
        return 0;
    }
    char *get_dic_encoding() {
        return encoding.data();
    }
    bool spell(const std::string &, int * = nullptr, std::string * = nullptr) {
        return true;
    }
    std::vector<std::string> suggest(const std::string &) {
        return std::vector<std::string>();
    }
    int add(const std::string &) {
        return 0;
    }

  private:
    QByteArray encoding;
};
#endif

#include <QDebug>
#include <QDir>
#include <QFile>
#include <QMutexLocker>
#include <QStandardPaths>
#include <QStringConverter>
#include <QTextStream>
#include "WordTrie.h"

class WordEngine::Private {
  public:
    bool          enabled  = true;
    QString       language = "en_US";
    QSet<QString> ignoredWords;
};

WordEngine::WordEngine(QObject *parent)
    : QObject(parent)
    , d(new Private)
    , m_workerThread(new QThread(this))
    , m_worker(nullptr) {
    initializeWorker();
}

WordEngine::~WordEngine() {
    if (m_workerThread && m_workerThread->isRunning()) {
        m_workerThread->quit();
        if (!m_workerThread->wait(3000)) {
            m_workerThread->terminate();
            m_workerThread->wait();
        }
    }
    delete d;
}

void WordEngine::initializeWorker() {
    m_worker = new WordEngineWorker();
    m_worker->moveToThread(m_workerThread);

    connect(m_worker, &WordEngineWorker::predictionsReady, this, &WordEngine::predictionsReady);
    connect(m_worker, &WordEngineWorker::errorOccurred, this, &WordEngine::errorOccurred);

    m_workerThread->start();

    if (d->enabled) {
        QMetaObject::invokeMethod(m_worker, "setLanguage", Qt::QueuedConnection,
                                  Q_ARG(QString, d->language));
    }
}

bool WordEngine::enabled() const {
    return d->enabled;
}

void WordEngine::setEnabled(bool on) {
    if (d->enabled == on)
        return;

    d->enabled = on;

    if (on) {
        QMetaObject::invokeMethod(m_worker, "setLanguage", Qt::QueuedConnection,
                                  Q_ARG(QString, d->language));
    }

    emit enabledChanged();
}

QString WordEngine::language() const {
    return d->language;
}

void WordEngine::setLanguage(const QString &lang) {
    if (d->language == lang)
        return;

    d->language = lang;

    if (d->enabled) {
        QMetaObject::invokeMethod(m_worker, "setLanguage", Qt::QueuedConnection,
                                  Q_ARG(QString, lang));
    }

    emit languageChanged();
}

bool WordEngine::hasWord(const QString &word) {
    return spell(word);
}

bool WordEngine::spell(const QString &word) {
    if (!d->enabled)
        return true;

    if (d->ignoredWords.contains(word))
        return true;

    return word.length() > 0;
}

void WordEngine::requestPredictions(const QString &prefix, int maxResults) {
    if (!d->enabled || prefix.isEmpty()) {
        emit predictionsReady(prefix, QStringList());
        return;
    }

    QMetaObject::invokeMethod(m_worker, "computePredictions", Qt::QueuedConnection,
                              Q_ARG(QString, prefix), Q_ARG(int, maxResults));
}

void WordEngine::learnWord(const QString &word) {
    if (!d->enabled || word.length() < 2)
        return;

    QMetaObject::invokeMethod(m_worker, "addWord", Qt::QueuedConnection, Q_ARG(QString, word));
}

void WordEngine::ignoreWord(const QString &word) {
    d->ignoredWords.insert(word);
}

QString WordEngine::dictionaryPath() {
    QStringList paths;

    paths << "/usr/share/hunspell"
          << "/usr/share/myspell/dicts"
          << "/usr/local/share/hunspell" << QDir::homePath() + "/.local/share/hunspell";

    for (const QString &path : paths) {
        if (QFile::exists(path)) {
            return path;
        }
    }

    return QString();
}

WordEngineWorker::WordEngineWorker(QObject *parent)
    : QObject(parent)
    , m_hunspell(nullptr)
    , m_trie(new WordTrie())
    , m_encoding("UTF-8")
    , m_language("en_US") {
    m_userDictionaryPath = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
        "/marathon-os/keyboard_user_dictionary.txt";
}

WordEngineWorker::~WordEngineWorker() {
    QMutexLocker locker(&m_mutex);
    delete m_hunspell;
    delete m_trie;
    m_hunspell = nullptr;
    m_trie     = nullptr;
}

void WordEngineWorker::setLanguage(const QString &language) {
    QMutexLocker locker(&m_mutex);

    m_language = language;

    if (!loadDictionary(language)) {
        emit errorOccurred(QString("Failed to load dictionary for %1").arg(language));
    } else {
        loadUserDictionary();
    }
}

bool WordEngineWorker::loadDictionary(const QString &language) {
    if (m_hunspell) {
        delete m_hunspell;
        m_hunspell = nullptr;
    }

    QString dictPath = findDictionaryPath(language);
    if (dictPath.isEmpty()) {
        return false;
    }

    QString affFile = dictPath + ".aff";
    QString dicFile = dictPath + ".dic";

    if (!QFile::exists(affFile) || !QFile::exists(dicFile)) {
        return false;
    }

    m_hunspell = new Hunspell(affFile.toUtf8().constData(), dicFile.toUtf8().constData());
    m_encoding = QString::fromLatin1(m_hunspell->get_dic_encoding());

    loadTrieFromDictionary(dicFile);

    return true;
}

QString WordEngineWorker::findDictionaryPath(const QString &language) {
    QStringList searchPaths;
    searchPaths << "/usr/share/hunspell"
                << "/usr/share/myspell/dicts"
                << "/usr/local/share/hunspell";

    for (const QString &basePath : searchPaths) {
        QDir dir(basePath);
        if (dir.exists(language + ".dic")) {
            return dir.filePath(language);
        }
    }

    QString langCode = language.left(2);
    for (const QString &basePath : searchPaths) {
        QDir        dir(basePath);
        QStringList dicFiles = dir.entryList(QStringList(langCode + "*.dic"));
        if (!dicFiles.isEmpty()) {
            QString dicName = dicFiles.first();
            dicName.chop(4);
            return dir.filePath(dicName);
        }
    }

    return QString();
}

void WordEngineWorker::loadUserDictionary() {
    if (!m_hunspell)
        return;

    QFile file(m_userDictionaryPath);
    if (!file.exists() || !file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }

    QTextStream stream(&file);
    while (!stream.atEnd()) {
        QString word = stream.readLine().trimmed();
        if (!word.isEmpty()) {
            m_hunspell->add(word.toStdString());
        }
    }
}

void WordEngineWorker::computePredictions(const QString &prefix, int maxResults) {
    QMutexLocker locker(&m_mutex);

    if (prefix.isEmpty()) {
        emit predictionsReady(prefix, QStringList());
        return;
    }

    QStringList results;

    if (m_trie && m_trie->size() > 0) {
        results = m_trie->getCompletions(prefix, maxResults);
    }

    if (results.size() < maxResults && m_hunspell) {
        QString lowerPrefix = prefix.toLower();
        auto    suggestions = m_hunspell->suggest(prefix.toStdString());

        for (const auto &s : suggestions) {
            if (results.size() >= maxResults)
                break;

            QString word = QString::fromStdString(s);
            if (word.toLower().startsWith(lowerPrefix) &&
                !results.contains(word, Qt::CaseInsensitive)) {
                results.append(word);
            }
        }
    }

    emit predictionsReady(prefix, results);
}

bool WordEngineWorker::loadTrieFromDictionary(const QString &dicPath) {
    if (!m_trie) {
        m_trie = new WordTrie();
    }

    m_trie->clear();

    QFile file(dicPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return false;
    }

    QTextStream stream(&file);
    QString     firstLine = stream.readLine();

    int         loadedCount = 0;
    const int   MAX_WORDS   = 50000;

    while (!stream.atEnd() && loadedCount < MAX_WORDS) {
        QString line = stream.readLine().trimmed();
        if (line.isEmpty())
            continue;

        int     slashPos = line.indexOf('/');
        QString baseWord = (slashPos >= 0) ? line.left(slashPos) : line;

        if (baseWord.length() >= 3 && baseWord.length() <= 20) {
            m_trie->insert(baseWord);
            loadedCount++;
        }
    }

    return loadedCount > 0;
}

void WordEngineWorker::addWord(const QString &word) {
    QMutexLocker locker(&m_mutex);

    if (word.length() < 2)
        return;

    if (m_trie) {
        m_trie->insert(word);
    }

    if (m_hunspell) {
        m_hunspell->add(word.toStdString());
    }

    QFile file(m_userDictionaryPath);
    QDir().mkpath(QFileInfo(file).absolutePath());

    if (file.open(QIODevice::Append | QIODevice::Text)) {
        QTextStream stream(&file);
        stream << word << '\n';
        stream.flush();
    }
}
