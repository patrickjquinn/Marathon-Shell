#include "configmanager.h"
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

ConfigManager* ConfigManager::s_instance = nullptr;

ConfigManager::ConfigManager(QObject *parent)
    : QObject(parent)
    , m_isLoaded(false)
    , m_version("1.0.0")
{
    s_instance = this;
    setDefaults();
}

ConfigManager::~ConfigManager()
{
    s_instance = nullptr;
}

ConfigManager* ConfigManager::instance()
{
    if (!s_instance) {
        s_instance = new ConfigManager();
    }
    return s_instance;
}

bool ConfigManager::loadConfig(const QString &filePath)
{
    qDebug() << "[ConfigManager] Loading config from:" << filePath;
    
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[ConfigManager] Failed to open config file:" << filePath;
        qWarning() << "[ConfigManager] Using default values";
        return false;
    }
    
    QByteArray data = file.readAll();
    file.close();
    
    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
    
    if (parseError.error != QJsonParseError::NoError) {
        qWarning() << "[ConfigManager] JSON parse error:" << parseError.errorString();
        qWarning() << "[ConfigManager] Using default values";
        return false;
    }
    
    if (!doc.isObject()) {
        qWarning() << "[ConfigManager] Config root must be a JSON object";
        return false;
    }
    
    QJsonObject root = doc.object();
    m_config = root.toVariantMap();
    m_version = m_config.value("version", "1.0.0").toString();
    m_isLoaded = true;
    
    qDebug() << "[ConfigManager] ✓ Config loaded successfully, version:" << m_version;
    return true;
}

QVariant ConfigManager::get(const QString &section, const QString &key, const QVariant &defaultValue) const
{
    if (!m_config.contains(section)) {
        return defaultValue;
    }
    
    QVariantMap sectionMap = m_config[section].toMap();
    return sectionMap.value(key, defaultValue);
}

void ConfigManager::setDefaults()
{
    // Set default values in case JSON fails to load
    // These match the values in marathon-config.json
    
    QVariantMap responsive;
    responsive["baseDPI"] = 160;
    responsive["baseHeight"] = 800;
    responsive["defaultUserScaleFactor"] = 1.0;
    m_config["responsive"] = responsive;
    
    QVariantMap zIndex;
    zIndex["background"] = 0;
    zIndex["mainContent"] = 90;
    zIndex["taskSwitcher"] = 200;
    zIndex["appWindow"] = 600;
    zIndex["lockScreen"] = 1000;
    zIndex["keyboard"] = 3000;
    m_config["zIndex"] = zIndex;
    
    QVariantMap gestures;
    gestures["edgeWidth"] = 50;
    gestures["peekThreshold"] = 100;
    gestures["commitThreshold"] = 200;
    gestures["quickSettingsDismissThreshold"] = 0.30;
    gestures["lockScreenSwipeDistance"] = 0.20;
    gestures["lockScreenCommitProgress"] = 0.25;
    m_config["gestures"] = gestures;
    
    QVariantMap animations;
    animations["fast"] = 150;
    animations["normal"] = 200;
    animations["slow"] = 300;
    animations["keyboardShow"] = 120;
    animations["lockScreenUnlock"] = 150;
    m_config["animations"] = animations;
    
    QVariantMap layout;
    layout["statusBarHeight"] = 44;
    layout["navBarHeight"] = 20;
    layout["bottomBarHeight"] = 100;
    layout["actionBarHeight"] = 72;
    m_config["layout"] = layout;
    
    QVariantMap typography;
    typography["xsmall"] = 12;
    typography["small"] = 14;
    typography["medium"] = 16;
    typography["large"] = 18;
    typography["xlarge"] = 24;
    typography["xxlarge"] = 32;
    typography["huge"] = 48;
    typography["gigantic"] = 96;
    typography["fontFamily"] = "Inter";
    typography["fontFamilyMono"] = "JetBrains Mono";
    m_config["typography"] = typography;
    
    QVariantMap spacing;
    spacing["xsmall"] = 5;
    spacing["small"] = 10;
    spacing["medium"] = 16;
    spacing["large"] = 20;
    spacing["xlarge"] = 32;
    spacing["xxlarge"] = 40;
    m_config["spacing"] = spacing;
    
    QVariantMap icons;
    icons["small"] = 20;
    icons["medium"] = 32;
    icons["large"] = 40;
    icons["xlarge"] = 64;
    icons["appSplash"] = 128;
    m_config["icons"] = icons;
    
    QVariantMap touchTargets;
    touchTargets["large"] = 90;
    touchTargets["medium"] = 70;
    touchTargets["small"] = 60;
    touchTargets["minimum"] = 45;
    m_config["touchTargets"] = touchTargets;
    
    QVariantMap appGrid;
    appGrid["iconSize"] = 72;
    appGrid["gridSpacing"] = 20;
    appGrid["columnsPhone"] = 4;
    appGrid["rowsPhone"] = 5;
    appGrid["phoneBreakpoint"] = 700;
    m_config["appGrid"] = appGrid;
    
    QVariantMap keyboard;
    keyboard["autoShow"] = true;
    keyboard["autoDismiss"] = true;
    m_config["keyboard"] = keyboard;
    
    QVariantMap features;
    features["enableWayland"] = true;
    features["enableBluetooth"] = true;
    features["enableWifi"] = true;
    m_config["features"] = features;
    
    QVariantMap bottomBar;
    bottomBar["iconMarginLeft"] = 20;
    bottomBar["iconMarginRight"] = 20;
    bottomBar["showPhoneShortcut"] = true;
    bottomBar["showCameraShortcut"] = true;
    m_config["bottomBar"] = bottomBar;
    
    qDebug() << "[ConfigManager] Default config initialized";
}

