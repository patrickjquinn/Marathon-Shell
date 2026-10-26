#pragma once

#include <QByteArray>
#include <QList>
#include <QObject>
#include <QStringList>

class QTranslator;

// The catalogs :/i18n/<catalog>_<code>.qm and Qt's own qtbase_<code>.qm,
// installed for one language at a time.
class Translations : public QObject {
    Q_OBJECT

  public:
    // Keeps LANG and LANGUAGE as they are now: the image's locale.
    Translations(const QStringList &catalogs, QObject *parent);

    // Also sets the default QLocale, LANG and LANGUAGE; an empty code restores
    // the image's. False when no catalog loaded.
    bool    install(const QString &code);
    QString code() const { return m_code; }

  signals:
    void installed(const QString &code);

  private:
    QStringList          m_catalogs;
    QByteArray           m_imageLang;
    QByteArray           m_imageLanguage;
    QString              m_code;
    QList<QTranslator *> m_translators;
};
