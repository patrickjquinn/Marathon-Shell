#pragma once

#include <QObject>
#include <QStringList>
#include <qqml.h>

class DomainSuggestions : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    explicit DomainSuggestions(QObject *parent = nullptr);

    Q_INVOKABLE QStringList getSuggestions(const QString &text, bool isEmail) const;
    Q_INVOKABLE bool        shouldShowDomainSuggestions(const QString &text, bool isEmail,
                                                        bool isUrl) const;

  private:
    QStringList m_commonTlds;
    QStringList m_emailDomains;
};
