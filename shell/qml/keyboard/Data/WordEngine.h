/*
 * Marathon Virtual Keyboard - Word Engine (Hunspell-based)
 * Adapted from Maliit Plugins spellchecker
 * 
 * Original Copyright (C) 2011 Nokia Corporation and/or its subsidiary(-ies).
 * Marathon adaptation Copyright (C) 2025 Marathon OS
 */

#ifndef MARATHON_WORDENGINE_H
#define MARATHON_WORDENGINE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QThread>
#include <QMutex>

class Hunspell;
class QTextCodec;
class WordEngineWorker;

/**
 * @brief Main word engine for spell-checking and predictions
 * 
 * Thread-safe wrapper around Hunspell for the Marathon keyboard.
 * Predictions run on a background thread to avoid blocking the UI.
 */
class WordEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)

  public:
    explicit WordEngine(QObject *parent = nullptr);
    ~WordEngine() override;

    // Properties
    bool    enabled() const;
    void    setEnabled(bool on);
    QString language() const;
    void    setLanguage(const QString &lang);

    // Synchronous spell-checking (fast enough for UI thread)
    Q_INVOKABLE bool hasWord(const QString &word);
    Q_INVOKABLE bool spell(const QString &word);

    // Asynchronous prediction (runs on worker thread)
    Q_INVOKABLE void requestPredictions(const QString &prefix, int maxResults = 3);

    // User dictionary management
    Q_INVOKABLE void learnWord(const QString &word);
    Q_INVOKABLE void ignoreWord(const QString &word);

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

/**
 * @brief Background worker for async predictions
 */
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
    QString   m_encoding; // Dictionary encoding (usually "UTF-8")
    QString   m_userDictionaryPath;
    QString   m_language;
    QMutex    m_mutex;

    bool      loadDictionary(const QString &language);
    void      loadUserDictionary();
    QString   findDictionaryPath(const QString &language);
};

#endif // MARATHON_WORDENGINE_H
