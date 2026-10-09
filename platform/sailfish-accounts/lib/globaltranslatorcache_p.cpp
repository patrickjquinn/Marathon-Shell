// SPDX-FileCopyrightText: 2014 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
//
// SPDX-License-Identifier: BSD-3-Clause
// Modified by Shipwright for Qt 6: QTranslator::load() is [[nodiscard]]; a missing
// catalogue still leaves the text untranslated, as upstream intends ((void) casts).

#include "globaltranslatorcache_p.h"
#include <QThreadStorage>
#include <QTranslator>
#include <QHash>
#include <QString>
#include <QByteArray>
#include <QFileInfo>
#include <QLocale>
#include <QCoreApplication>
#include <QtDebug>

#include <Accounts/Provider>
#include <Accounts/Service>
#include <Accounts/ServiceType>

namespace SailfishAccounts {

static QTranslator* libEngEngTranslator = nullptr;
static QTranslator* libTranslator = nullptr;

void initLibTranslator()
{
    if (!libEngEngTranslator) {
        libEngEngTranslator = new QTranslator(qApp);
        (void)libEngEngTranslator->load(QString::fromLatin1("sailfishaccounts_eng_en"),
                                  QString::fromLatin1("/usr/share/translations"));
        qApp->installTranslator(libEngEngTranslator);

        libTranslator = new QTranslator(qApp);
        (void)libTranslator->load(QLocale(), QString::fromLatin1("sailfishaccounts"), QString::fromLatin1("-"),
                            QString::fromLatin1("/usr/share/translations"));
        qApp->installTranslator(libTranslator);
    }
}


class TranslatorManager
{
public:
    mutable QHash<QString, QTranslator*> translators;

    QTranslator *translator(const QString &trCatalog, bool engineeringEnglish)
    {
        QTranslator *translator = 0;
        QString catalogName = engineeringEnglish ? (trCatalog + QLatin1String("_eng_en")) : trCatalog;

        if (!translators.contains(catalogName)) {
            QFileInfo fi(catalogName);
            translator = new QTranslator;
            if (fi.isAbsolute()) {
                if (fi.exists()) {
                    // fully specified path to file
                    // engineering version just skipped, combination doesn't make sense
                    if (!engineeringEnglish) {
                        (void)translator->load(catalogName);
                    }
                } else {
                    // partially specified path to file
                    QString trPath = fi.path();
                    QString trFile = fi.fileName();
                    if (engineeringEnglish) {
                        (void)translator->load(trFile, trPath);
                    } else {
                        (void)translator->load(QLocale(), trFile, "-", trPath);
                    }
                }
            } else {
                if (engineeringEnglish) {
                    (void)translator->load(catalogName, "/usr/share/translations");
                } else {
                    (void)translator->load(QLocale(), catalogName, "-", "/usr/share/translations");
                }
            }
            translators.insert(catalogName, translator);
        } else {
            translator = translators.value(catalogName);
        }
        return translator;
    }

    ~TranslatorManager()
    {
        qDeleteAll(translators.values());
    }
};

static QThreadStorage<TranslatorManager*> g_translationManager;

static QTranslator *cachedTranslator(const QString &trCatalog, bool engineeringEnglish)
{
    if (!g_translationManager.hasLocalData()) {
        g_translationManager.setLocalData(new TranslatorManager);
    }

    TranslatorManager *manager = g_translationManager.localData();
    return manager ? manager->translator(trCatalog, engineeringEnglish) : 0;
}

#define RETURN_TRANSLATED_DISPLAYNAME(instance)                                                         \
    do {                                                                                                \
        if (instance.trCatalog().isEmpty()) return instance.displayName();                              \
        QByteArray translationId = instance.displayName().toLatin1();                                   \
        QTranslator *translator = cachedTranslator(instance.trCatalog(), false);                        \
        QString retn = translator ? translator->translate("", translationId.constData()) : QString();   \
        if (!retn.isEmpty() && retn != translationId.constData()) return retn;                          \
        translator = cachedTranslator(instance.trCatalog(), true);                                      \
        retn = translator ? translator->translate("", translationId.constData()) : QString();           \
        return retn.isEmpty() ? instance.displayName() : retn;                                          \
    } while (0)                                                                                         \

QString translatedDisplayName(const Accounts::Provider &provider)
{
    RETURN_TRANSLATED_DISPLAYNAME(provider);
}

QString translatedDisplayName(const Accounts::Service &service)
{
    RETURN_TRANSLATED_DISPLAYNAME(service);
}

QString translatedDisplayName(const Accounts::ServiceType &serviceType)
{
    RETURN_TRANSLATED_DISPLAYNAME(serviceType);
}

#undef RETURN_TRANSLATED_DISPLAYNAME

}
