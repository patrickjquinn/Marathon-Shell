// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Plugin class for Sailfish.Silica. Registers the module's declarative types
// (QML files, Clipboard, EnterKey; Theme is Keel.SilicaCore's, which this
// module re-exports: coreplugin.cpp) and installs the "theme" image provider on
// each engine that imports the module, the "keelambience" image provider
// (ambienceimageprovider.h), the `screen` context property and the
// translations of Silica's BSD QML strings (translator.h).

#include "ambienceimageprovider.h"
#include "screen.h"
#include "themeimageprovider.h"
#include "translator.h"
#include "windowdefaults.h"

#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlEngineExtensionPlugin>
#include <QPointer>
#include <QTimer>

extern void qml_register_types_Sailfish_Silica();

// Keeps the provider's colour scheme (it picks <name>-light / <name>-dark
// icon variants) and pixel ratio (z<ratio> icon directories) in step with
// the engine's Keel.Ambience singleton.
class KeelThemeSchemeFollower : public QObject
{
    Q_OBJECT
public:
    KeelThemeSchemeFollower(QObject *ambience, KeelThemeImageProvider *provider)
        : QObject(ambience), m_ambience(ambience), m_provider(provider)
    {
        update();
        connect(ambience, SIGNAL(ambienceChanged()), this, SLOT(update()));
    }

public slots:
    // Theme.ColorScheme: 0 LightOnDark, 1 DarkOnLight. The provider is owned
    // by the engine, which outlives its singletons (and so this object).
    void update()
    {
        m_provider->setLightScheme(m_ambience->property("colorScheme").toInt() == 1);
        // The theme's z<ratio> icons (dconf's theme_pixel_ratio on a phone).
        const double ratio = m_ambience->property("pixelRatio").toDouble();
        if (ratio > 0)
            m_provider->setPixelRatio(ratio);
    }

private:
    QObject *m_ambience;
    KeelThemeImageProvider *m_provider;
};

static void followAmbience(QQmlEngine *engine, KeelThemeImageProvider *provider, int attempt = 0)
{
    const int id = qmlTypeId("Keel", 1, 0, "Ambience");
    if (QObject *ambience = id >= 0 ? engine->singletonInstance<QObject *>(id) : nullptr) {
        new KeelThemeSchemeFollower(ambience, provider);
        return;
    }
    // Keel (a dependency of this module) may register its types only after
    // this plugin: try again once the event loop runs.
    if (attempt < 50) {
        QPointer<QQmlEngine> e(engine);
        QTimer::singleShot(attempt ? 20 : 0, engine, [e, provider, attempt] {
            if (e)
                followAmbience(e, provider, attempt + 1);
        });
    }
}

class SailfishSilicaPlugin : public QQmlEngineExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlEngineExtensionInterface_iid)

public:
    explicit SailfishSilicaPlugin(QObject *parent = nullptr)
        : QQmlEngineExtensionPlugin(parent)
    {
        volatile auto registration = &qml_register_types_Sailfish_Silica;
        Q_UNUSED(registration)
    }

    void initializeEngine(QQmlEngine *engine, const char *uri) override
    {
        Q_UNUSED(uri)
        if (!engine->imageProvider(QStringLiteral("theme"))) {
            auto *provider = new KeelThemeImageProvider;
            engine->addImageProvider(QStringLiteral("theme"), provider);
            followAmbience(engine, provider);
        }
        if (!engine->imageProvider(QStringLiteral("keelambience")))
            engine->addImageProvider(QStringLiteral("keelambience"), new KeelAmbienceImageProvider);
        // Silica's BSD QML reads `screen.sizeCategory` (lower case): the
        // Screen singleton as a context property of the engine.
        if (!engine->rootContext()->contextProperty(QStringLiteral("screen")).isValid())
            engine->rootContext()->setContextProperty(QStringLiteral("screen"), new KeelScreen(engine));
        if (!engine->rootContext()->contextProperty(QStringLiteral("__silica_applicationwindow_instance")).isValid())
            engine->rootContext()->setContextProperty(QStringLiteral("__silica_applicationwindow_instance"),
                                                      new KeelWindowDefaults(engine));
        keel::installSilicaTranslations();
    }
};

#include "silicaplugin.moc"
