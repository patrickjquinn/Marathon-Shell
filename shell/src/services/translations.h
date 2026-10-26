#pragma once

#include <QList>
#include <QObject>
#include <QStringList>

class QTranslator;

// The catalogs :/i18n/<catalog>_<code>.qm and Qt's own qtbase_<code>.qm,
// installed for one language at a time.
class Translations : public QObject {
    Q_OBJECT

  public:
    Translations(const QStringList &catalogs, QObject *parent);

    // Also sets the default QLocale, LANG and LANGUAGE. False when no catalog loaded.
    bool    install(const QString &code);
    QString code() const { return m_code; }

  signals:
    void installed(const QString &code);

  private:
    QStringList          m_catalogs;
    QString              m_code;
    QList<QTranslator *> m_translators;
};
