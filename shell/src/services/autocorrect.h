#pragma once

#include <QHash>
#include <QObject>
#include <QString>
#include <qqml.h>

class Dictionary;

class AutoCorrect : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

  public:
    explicit AutoCorrect(Dictionary *dictionary, QObject *parent = nullptr);

    bool enabled() const {
        return m_enabled;
    }
    void                setEnabled(bool enabled);

    Q_INVOKABLE QString correct(const QString &word);
    Q_INVOKABLE QString shouldCorrect(const QString &word);
    Q_INVOKABLE void    learnCorrection(const QString &typo, const QString &correction);

  signals:
    void enabledChanged();

  private:
    int                     levenshteinDistance(const QString &first, const QString &second) const;

    Dictionary             *m_dictionary;
    QHash<QString, QString> m_commonTypos;
    bool                    m_enabled = true;
};
