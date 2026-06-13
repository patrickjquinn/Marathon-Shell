#pragma once

class QQmlEngine;
class QJSEngine;

#include <QObject>
#include <QStringList>
#include <qqml.h>

class DomainSuggestions : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
  public:
    // QML_SINGLETON factory — required so the type registers correctly in
    // marathon-app-runner processes that import this module without the
    // shell's explicit qmlRegisterSingletonInstance call. Shell process
    // still calls qmlRegisterSingletonInstance in main.cpp; that override
    // wins so shell-side C++ consumers share the same instance pointer.
    static DomainSuggestions *create(QQmlEngine *, QJSEngine *);

  public:
    explicit DomainSuggestions(QObject *parent = nullptr);

    Q_INVOKABLE QStringList getSuggestions(const QString &text, bool isEmail) const;
    Q_INVOKABLE bool        shouldShowDomainSuggestions(const QString &text, bool isEmail,
                                                        bool isUrl) const;

  private:
    QStringList m_commonTlds;
    QStringList m_emailDomains;
};
