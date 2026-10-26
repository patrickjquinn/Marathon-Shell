#include "translations.h"

#include <QCoreApplication>
#include <QLibraryInfo>
#include <QLocale>
#include <QTranslator>

Translations::Translations(const QStringList &catalogs, QObject *parent)
    : QObject(parent), m_catalogs(catalogs) {}

bool Translations::install(const QString &code) {
    qDeleteAll(m_translators);
    m_translators.clear();

    const auto load = [this](const QString &file, const QString &directory) {
        auto *translator = new QTranslator(this);
        if (!translator->load(file, directory) || !QCoreApplication::installTranslator(translator)) {
            delete translator;
            return false;
        }
        m_translators.append(translator);
        return true;
    };
    load(QStringLiteral("qtbase_") + code, QLibraryInfo::path(QLibraryInfo::TranslationsPath));
    bool loaded = false;
    for (const QString &catalog : std::as_const(m_catalogs))
        loaded |= load(catalog + QLatin1Char('_') + code, QStringLiteral(":/i18n"));

    QLocale::setDefault(QLocale(code == QLatin1String("en_XA") ? QStringLiteral("en") : code));
    qputenv("LANG", code.toUtf8() + ".UTF-8");
    qputenv("LANGUAGE", code.toUtf8());
    m_code = code;
    emit installed(code);
    return loaded;
}
