#ifndef CONFIGMANAGER_H
#define CONFIGMANAGER_H

#include <QObject>
#include <QVariantMap>
#include <QString>
#include <QJsonObject>

/**
 * @brief ConfigManager - Loads marathon-config.json at build time
 * 
 * Acts like Android's build.xml - provides centralized configuration
 * for all hardcoded values across the shell. Values can be overridden
 * at build time by modifying marathon-config.json.
 * 
 * Exposed to QML as a singleton via qmlRegisterSingletonType.
 */
class ConfigManager : public QObject
{
    Q_OBJECT
    
    // Expose entire config tree to QML
    Q_PROPERTY(QVariantMap responsive READ responsive CONSTANT)
    Q_PROPERTY(QVariantMap zIndex READ zIndex CONSTANT)
    Q_PROPERTY(QVariantMap gestures READ gestures CONSTANT)
    Q_PROPERTY(QVariantMap animations READ animations CONSTANT)
    Q_PROPERTY(QVariantMap session READ session CONSTANT)
    Q_PROPERTY(QVariantMap performance READ performance CONSTANT)
    Q_PROPERTY(QVariantMap keyboard READ keyboard CONSTANT)
    Q_PROPERTY(QVariantMap layout READ layout CONSTANT)
    Q_PROPERTY(QVariantMap safeArea READ safeArea CONSTANT)
    Q_PROPERTY(QVariantMap pageIndicators READ pageIndicators CONSTANT)
    Q_PROPERTY(QVariantMap lockScreen READ lockScreen CONSTANT)
    Q_PROPERTY(QVariantMap scrolling READ scrolling CONSTANT)
    Q_PROPERTY(QVariantMap touchTargets READ touchTargets CONSTANT)
    Q_PROPERTY(QVariantMap appGrid READ appGrid CONSTANT)
    Q_PROPERTY(QVariantMap cards READ cards CONSTANT)
    Q_PROPERTY(QVariantMap typography READ typography CONSTANT)
    Q_PROPERTY(QVariantMap spacing READ spacing CONSTANT)
    Q_PROPERTY(QVariantMap borders READ borders CONSTANT)
    Q_PROPERTY(QVariantMap icons READ icons CONSTANT)
    Q_PROPERTY(QVariantMap shadows READ shadows CONSTANT)
    Q_PROPERTY(QVariantMap modals READ modals CONSTANT)
    Q_PROPERTY(QVariantMap quickSettings READ quickSettings CONSTANT)
    Q_PROPERTY(QVariantMap statusBar READ statusBar CONSTANT)
    Q_PROPERTY(QVariantMap navBar READ navBar CONSTANT)
    Q_PROPERTY(QVariantMap taskSwitcher READ taskSwitcher CONSTANT)
    Q_PROPERTY(QVariantMap bottomBar READ bottomBar CONSTANT)
    Q_PROPERTY(QVariantMap features READ features CONSTANT)
    Q_PROPERTY(QVariantMap debug READ debug CONSTANT)
    
    Q_PROPERTY(bool isLoaded READ isLoaded CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)

public:
    explicit ConfigManager(QObject *parent = nullptr);
    ~ConfigManager();
    
    // Singleton instance
    static ConfigManager* instance();
    
    // Load config from file (called once at startup)
    bool loadConfig(const QString &filePath = ":/marathon-config.json");
    
    // Getters for QML
    QVariantMap responsive() const { return m_config["responsive"].toMap(); }
    QVariantMap zIndex() const { return m_config["zIndex"].toMap(); }
    QVariantMap gestures() const { return m_config["gestures"].toMap(); }
    QVariantMap animations() const { return m_config["animations"].toMap(); }
    QVariantMap session() const { return m_config["session"].toMap(); }
    QVariantMap performance() const { return m_config["performance"].toMap(); }
    QVariantMap keyboard() const { return m_config["keyboard"].toMap(); }
    QVariantMap layout() const { return m_config["layout"].toMap(); }
    QVariantMap safeArea() const { return m_config["safeArea"].toMap(); }
    QVariantMap pageIndicators() const { return m_config["pageIndicators"].toMap(); }
    QVariantMap lockScreen() const { return m_config["lockScreen"].toMap(); }
    QVariantMap scrolling() const { return m_config["scrolling"].toMap(); }
    QVariantMap touchTargets() const { return m_config["touchTargets"].toMap(); }
    QVariantMap appGrid() const { return m_config["appGrid"].toMap(); }
    QVariantMap cards() const { return m_config["cards"].toMap(); }
    QVariantMap typography() const { return m_config["typography"].toMap(); }
    QVariantMap spacing() const { return m_config["spacing"].toMap(); }
    QVariantMap borders() const { return m_config["borders"].toMap(); }
    QVariantMap icons() const { return m_config["icons"].toMap(); }
    QVariantMap shadows() const { return m_config["shadows"].toMap(); }
    QVariantMap modals() const { return m_config["modals"].toMap(); }
    QVariantMap quickSettings() const { return m_config["quickSettings"].toMap(); }
    QVariantMap statusBar() const { return m_config["statusBar"].toMap(); }
    QVariantMap navBar() const { return m_config["navBar"].toMap(); }
    QVariantMap taskSwitcher() const { return m_config["taskSwitcher"].toMap(); }
    QVariantMap bottomBar() const { return m_config["bottomBar"].toMap(); }
    QVariantMap features() const { return m_config["features"].toMap(); }
    QVariantMap debug() const { return m_config["debug"].toMap(); }
    
    bool isLoaded() const { return m_isLoaded; }
    QString version() const { return m_version; }
    
    // Helper to get nested values
    Q_INVOKABLE QVariant get(const QString &section, const QString &key, const QVariant &defaultValue = QVariant()) const;

private:
    static ConfigManager* s_instance;
    
    QVariantMap m_config;
    bool m_isLoaded;
    QString m_version;
    
    void setDefaults();
};

#endif // CONFIGMANAGER_H

