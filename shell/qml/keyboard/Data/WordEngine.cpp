/*
 * Marathon Virtual Keyboard - Word Engine Implementation
 * Adapted from Maliit Plugins spellchecker
 */

#include "WordEngine.h"

#ifdef HAVE_HUNSPELL
#include <hunspell/hunspell.hxx>
#else
// Stub implementation if Hunspell is not available
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
#include <QTextStream>
#include <QStringConverter>
#include <QStandardPaths>
#include <QMutexLocker>

// ======================
// WordEngine::Private
// ======================

class WordEngine::Private {
  public:
    bool          enabled  = false;
    QString       language = "en_US";
    QSet<QString> ignoredWords;
};

// ======================
// WordEngine
// ======================

WordEngine::WordEngine(QObject *parent)
    : QObject(parent)
    , d(new Private)
    , m_workerThread(new QThread(this))
    , m_worker(nullptr) {
    qDebug() << "[WordEngine] Initializing...";
    initializeWorker();
}

WordEngine::~WordEngine() {
    qDebug() << "[WordEngine] Shutting down worker thread...";
    if (m_workerThread && m_workerThread->isRunning()) {
        m_workerThread->quit();
        if (!m_workerThread->wait(3000)) {
            qWarning() << "[WordEngine] Worker thread did not finish in time, terminating...";
            m_workerThread->terminate();
            m_workerThread->wait();
        }
    }
    delete d;
}

void WordEngine::initializeWorker() {
    m_worker = new WordEngineWorker();
    m_worker->moveToThread(m_workerThread);

    // Connect signals
    connect(m_worker, &WordEngineWorker::predictionsReady, this, &WordEngine::predictionsReady);
    connect(m_worker, &WordEngineWorker::errorOccurred, this, &WordEngine::errorOccurred);

    // Start worker thread
    m_workerThread->start();
    qDebug() << "[WordEngine] Worker thread started";
}

bool WordEngine::enabled() const {
    return d->enabled;
}

void WordEngine::setEnabled(bool on) {
    if (d->enabled == on)
        return;

    d->enabled = on;

    if (on) {
        // Initialize Hunspell on worker thread
        QMetaObject::invokeMethod(m_worker, "setLanguage", Qt::QueuedConnection,
                                  Q_ARG(QString, d->language));
    }

    qDebug() << "[WordEngine] Enabled:" << on;
    emit enabledChanged();
}

QString WordEngine::language() const {
    return d->language;
}

void WordEngine::setLanguage(const QString &lang) {
    if (d->language == lang)
        return;

    d->language = lang;
    qDebug() << "[WordEngine] Language set to:" << lang;

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

    // For now, use simple dictionary check
    // TODO: Add sync Hunspell check if needed
    return word.length() > 0;
}

void WordEngine::requestPredictions(const QString &prefix, int maxResults) {
    if (!d->enabled || prefix.isEmpty()) {
        emit predictionsReady(prefix, QStringList());
        return;
    }

    // Invoke worker asynchronously
    QMetaObject::invokeMethod(m_worker, "computePredictions", Qt::QueuedConnection,
                              Q_ARG(QString, prefix), Q_ARG(int, maxResults));
}

void WordEngine::learnWord(const QString &word) {
    if (!d->enabled || word.length() < 2)
        return;

    qDebug() << "[WordEngine] Learning word:" << word;
    QMetaObject::invokeMethod(m_worker, "addWord", Qt::QueuedConnection, Q_ARG(QString, word));
}

void WordEngine::ignoreWord(const QString &word) {
    d->ignoredWords.insert(word);
    qDebug() << "[WordEngine] Ignoring word:" << word;
}

QString WordEngine::dictionaryPath() {
    QStringList paths;

    // Check common Hunspell dictionary locations
    paths << "/usr/share/hunspell"
          << "/usr/share/myspell/dicts"
          << "/usr/local/share/hunspell" << QDir::homePath() + "/.local/share/hunspell";

    for (const QString &path : paths) {
        if (QFile::exists(path)) {
            qDebug() << "[WordEngine] Found dictionary path:" << path;
            return path;
        }
    }

    qWarning() << "[WordEngine] No Hunspell dictionaries found!";
    return QString();
}

// ======================
// WordEngineWorker
// ======================

WordEngineWorker::WordEngineWorker(QObject *parent)
    : QObject(parent)
    , m_hunspell(nullptr)
    , m_encoding("UTF-8")
    , m_language("en_US") {
    m_userDictionaryPath = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation) +
        "/marathon-os/keyboard_user_dictionary.txt";
    qDebug() << "[WordEngineWorker] User dictionary:" << m_userDictionaryPath;
}

WordEngineWorker::~WordEngineWorker() {
    QMutexLocker locker(&m_mutex);
    delete m_hunspell;
    m_hunspell = nullptr;
}

void WordEngineWorker::setLanguage(const QString &language) {
    QMutexLocker locker(&m_mutex);

    qDebug() << "[WordEngineWorker] Setting language to:" << language;
    m_language = language;

    if (!loadDictionary(language)) {
        emit errorOccurred(QString("Failed to load dictionary for %1").arg(language));
    } else {
        loadUserDictionary();
    }
}

bool WordEngineWorker::loadDictionary(const QString &language) {
    // Clean up existing
    if (m_hunspell) {
        delete m_hunspell;
        m_hunspell = nullptr;
    }

    QString dictPath = findDictionaryPath(language);
    if (dictPath.isEmpty()) {
        qWarning() << "[WordEngineWorker] No dictionary found for" << language;
        return false;
    }

    QString affFile = dictPath + ".aff";
    QString dicFile = dictPath + ".dic";

    if (!QFile::exists(affFile) || !QFile::exists(dicFile)) {
        qWarning() << "[WordEngineWorker] Dictionary files not found:" << affFile << dicFile;
        return false;
    }

    qDebug() << "[WordEngineWorker] Loading dictionary:" << affFile << dicFile;

    m_hunspell = new Hunspell(affFile.toUtf8().constData(), dicFile.toUtf8().constData());

    // Get dictionary encoding (usually UTF-8)
    m_encoding = QString::fromLatin1(m_hunspell->get_dic_encoding());
    qDebug() << "[WordEngineWorker] Dictionary encoding:" << m_encoding;

    qDebug() << "[WordEngineWorker] Dictionary loaded successfully";
    return true;
}

QString WordEngineWorker::findDictionaryPath(const QString &language) {
    QStringList searchPaths;
    searchPaths << "/usr/share/hunspell"
                << "/usr/share/myspell/dicts"
                << "/usr/local/share/hunspell";

    // Try exact match first (e.g., "en_US")
    for (const QString &basePath : searchPaths) {
        QDir dir(basePath);
        if (dir.exists(language + ".dic")) {
            return dir.filePath(language);
        }
    }

    // Try language code only (e.g., "en" from "en_US")
    QString langCode = language.left(2);
    for (const QString &basePath : searchPaths) {
        QDir        dir(basePath);
        QStringList dicFiles = dir.entryList(QStringList(langCode + "*.dic"));
        if (!dicFiles.isEmpty()) {
            QString dicName = dicFiles.first();
            dicName.chop(4); // Remove ".dic"
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
    int         count = 0;
    while (!stream.atEnd()) {
        QString word = stream.readLine().trimmed();
        if (!word.isEmpty()) {
            m_hunspell->add(word.toStdString());
            count++;
        }
    }

    qDebug() << "[WordEngineWorker] Loaded" << count << "words from user dictionary";
}

void WordEngineWorker::computePredictions(const QString &prefix, int maxResults) {
    QMutexLocker locker(&m_mutex);

    if (!m_hunspell || prefix.isEmpty()) {
        emit predictionsReady(prefix, QStringList());
        return;
    }

    // Get suggestions from Hunspell
    auto suggestions = m_hunspell->suggest(prefix.toStdString());

    // Determine if prefix is lowercase for case normalization
    bool        isLowercase = prefix[0].isLower();

    QStringList results;
    for (const auto &s : suggestions) {
        if (results.size() >= maxResults)
            break;

        QString word = QString::fromStdString(s);
        // Only include words that start with the prefix
        if (word.toLower().startsWith(prefix.toLower())) {
            // Normalize case to match user input (Maliit behavior)
            if (isLowercase) {
                word = word.toLower();
            }
            results.append(word);
        }
    }

    emit predictionsReady(prefix, results);
}

void WordEngineWorker::addWord(const QString &word) {
    QMutexLocker locker(&m_mutex);

    if (!m_hunspell || word.length() < 2)
        return;

    // Add to Hunspell
    m_hunspell->add(word.toStdString());

    // Save to user dictionary
    QFile file(m_userDictionaryPath);
    QDir().mkpath(QFileInfo(file).absolutePath());

    if (file.open(QIODevice::Append | QIODevice::Text)) {
        QTextStream stream(&file);
        stream << word << '\n';
        stream.flush();
        qDebug() << "[WordEngineWorker] Added word to user dictionary:" << word;
    }
}
