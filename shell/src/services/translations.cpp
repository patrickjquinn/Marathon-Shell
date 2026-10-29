#include "translations.h"

#include <QCoreApplication>
#include <QLibraryInfo>
#include <QLocale>
#include <QTranslator>

Translations::Translations(const QStringList &catalogs, QObject *parent)
    : QObject(parent)
    , m_catalogs(catalogs)
    , m_imageLang(qgetenv("LANG"))
    , m_imageLanguage(qgetenv("LANGUAGE")) {}

static void restore(const char *name, const QByteArray &value) {
    if (value.isEmpty())
        qunsetenv(name);
    else
        qputenv(name, value);
}

bool Translations::install(const QString &code) {
    qDeleteAll(m_translators);
    m_translators.clear();

    const QLocale locale = code.isEmpty() ?
        QLocale(QString::fromLocal8Bit(m_imageLang)) :
        QLocale(code == QLatin1String("en_XA") ? QStringLiteral("en") : code);
    const auto    load = [this, &code, &locale](const QString &catalog, const QString &directory) {
        auto      *translator = new QTranslator(this);
        const bool found      = code.isEmpty() ?
            translator->load(locale, catalog, QStringLiteral("_"), directory) :
            translator->load(catalog + QLatin1Char('_') + code, directory);
        if (!found || !QCoreApplication::installTranslator(translator)) {
            delete translator;
            return false;
        }
        m_translators.append(translator);
        return true;
    };
    load(QStringLiteral("qtbase"), QLibraryInfo::path(QLibraryInfo::TranslationsPath));
    bool loaded = false;
    for (const QString &catalog : std::as_const(m_catalogs))
        loaded |= load(catalog, QStringLiteral(":/i18n"));

    QLocale::setDefault(locale);
    if (code.isEmpty()) {
        restore("LANG", m_imageLang);
        restore("LANGUAGE", m_imageLanguage);
    } else {
        qputenv("LANG", locale.name().toUtf8() + ".UTF-8");
        qputenv("LANGUAGE", code.toUtf8());
    }
    m_code = code;
    emit installed(code);
    return loaded;
}
