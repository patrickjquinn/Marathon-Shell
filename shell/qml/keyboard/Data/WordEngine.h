#ifndef MARATHON_WORDENGINE_H
#define MARATHON_WORDENGINE_H

#include <QMutex>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QThread>

class Hunspell;
class QTextCodec;
class WordEngineWorker;

class WordEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)

  public:
    explicit WordEngine(QObject *parent = nullptr);
    ~WordEngine() override;

    bool                enabled() const;
    Q_INVOKABLE void    setEnabled(bool on);
    Q_INVOKABLE QString language() const;
    Q_INVOKABLE void    setLanguage(const QString &lang);

    Q_INVOKABLE bool    hasWord(const QString &word);
    Q_INVOKABLE bool    spell(const QString &word);
    Q_INVOKABLE void    requestPredictions(const QString &prefix, int maxResults = 3);
    Q_INVOKABLE void    learnWord(const QString &word);
    Q_INVOKABLE void    ignoreWord(const QString &word);

  signals:
    void enabledChanged();
    void languageChanged();
    void predictionsReady(QString prefix, QStringList predictions);
    void errorOccurred(QString message);

  private:
    class Private;
    Private          *d;

    QThread          *m_workerThread;
    WordEngineWorker *m_worker;

    static QString    dictionaryPath();
    void              initializeWorker();
};

class WordEngineWorker : public QObject {
    Q_OBJECT

  public:
    explicit WordEngineWorker(QObject *parent = nullptr);
    ~WordEngineWorker() override;

  public slots:
    void setLanguage(const QString &language);
    void computePredictions(const QString &prefix, int maxResults);
    void addWord(const QString &word);

  signals:
    void predictionsReady(QString prefix, QStringList predictions);
    void errorOccurred(QString message);

  private:
    Hunspell *m_hunspell;
    QString   m_encoding;
    QString   m_userDictionaryPath;
    QString   m_language;
    QMutex    m_mutex;

    bool      loadDictionary(const QString &language);
    void      loadUserDictionary();
    QString   findDictionaryPath(const QString &language);
};

#endif
