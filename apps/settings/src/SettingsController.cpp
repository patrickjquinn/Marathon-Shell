#include "SettingsController.h"

#include <QFile>
#include <QGuiApplication>
#include <QJSEngine>
#include <QMetaType>
#include <QOperatingSystemVersion>
#include <QQmlContext>
#include <QQmlEngine>
#include <QScreen>

SettingsController *SettingsController::create(QQmlEngine *engine, QJSEngine *) {
    auto *m = new SettingsController(engine);
    QQmlEngine::setObjectOwnership(m, QQmlEngine::CppOwnership);
    return m;
}
#include <QSysInfo>
#include <QTimer>
#include <algorithm>

SettingsController::SettingsController(QObject *parent)
    : QObject(parent) {
    updateSystemInfo();
    auto makeItem = [](const QString &title, const QString &subtitle, const QString &value) {
        QVariantMap item;
        item.insert("title", title);
        item.insert("subtitle", subtitle);
        item.insert("value", value);
        return item;
    };
    auto makeSection = [](const QString &title, const QVariantList &items) {
        QVariantMap section;
        section.insert("title", title);
        section.insert("items", items);
        return section;
    };
    QVariantList coreItems;
    coreItems.append(makeItem(QStringLiteral("Marathon Shell"),
                              QStringLiteral("Core shell and system apps"),
                              QStringLiteral("Apache-2.0")));
    QVariantList thirdPartyItems;
    thirdPartyItems.append(makeItem(QStringLiteral("Qt 6"),
                                    QStringLiteral("Qt Core, QML, Quick, Wayland, WebEngine"),
                                    QStringLiteral("LGPL-3.0 / GPL-3.0")));
    thirdPartyItems.append(makeItem(
        QStringLiteral("LunaSVG"), QStringLiteral("SVG rendering backend"), QStringLiteral("MIT")));
    thirdPartyItems.append(makeItem(QStringLiteral("PlutoVG"),
                                    QStringLiteral("Vector graphics rasterizer (via LunaSVG)"),
                                    QStringLiteral("MIT")));
    thirdPartyItems.append(makeItem(QStringLiteral("Hunspell"),
                                    QStringLiteral("Spell checking and predictions"),
                                    QStringLiteral("MPL-1.1 / LGPL-2.1 / GPL-2.0")));
    thirdPartyItems.append(makeItem(QStringLiteral("Wayland Protocols"),
                                    QStringLiteral("Wayland compositor + protocols"),
                                    QStringLiteral("MIT")));
    thirdPartyItems.append(makeItem(QStringLiteral("GStreamer"),
                                    QStringLiteral("Media playback backend"),
                                    QStringLiteral("LGPL-2.1")));
    thirdPartyItems.append(makeItem(QStringLiteral("PulseAudio"),
                                    QStringLiteral("Audio routing backend"),
                                    QStringLiteral("LGPL-2.1")));
    thirdPartyItems.append(makeItem(QStringLiteral("Linux-PAM"),
                                    QStringLiteral("Authentication framework"),
                                    QStringLiteral("BSD-3-Clause")));
    m_openSourceLicenses.append(makeSection(QStringLiteral("Marathon OS"), coreItems));
    m_openSourceLicenses.append(
        makeSection(QStringLiteral("Third-party components"), thirdPartyItems));
    QTimer::singleShot(0, this, &SettingsController::resolveDependencies);
}

void SettingsController::setNotificationEnabled(const QString &appId, bool enabled) {
    if (!m_settingsManager) {
        resolveDependencies();
    }
    if (!m_settingsManager) {
        return;
    }
    QVariantMap settings = m_settingsManager->property("appNotificationSettings").toMap();
    settings.insert(appId, enabled);
    m_settingsManager->setProperty("appNotificationSettings", settings);
}

void SettingsController::showWifiDialog(const QString &ssid, int strength, const QString &security,
                                        bool secured) {
    if (ssid != m_wifiDialogSsid || m_wifiDialogHidden)
        m_wifiDialogPassword.clear();
    m_wifiDialogHidden     = false;
    m_wifiDialogSsid       = ssid;
    m_wifiDialogStrength   = strength;
    m_wifiDialogSecurity   = security.isEmpty() ? QStringLiteral("WPA2") : security;
    m_wifiDialogSecured    = secured;
    m_wifiDialogConnecting = false;
    m_wifiDialogError.clear();
    setWifiDialogVisible(true);
}

void SettingsController::dismissWifiDialog() {
    setWifiDialogVisible(false);
}

void SettingsController::submitWifiPassword(const QString &password) {
    if (!m_networkManager) {
        resolveDependencies();
    }
    if (!m_networkManager) {
        return;
    }
    m_wifiDialogConnecting = true;
    m_wifiDialogPassword   = password;
    m_wifiDialogError.clear();
    emit wifiDialogChanged();
    QMetaObject::invokeMethod(m_networkManager, "connectToNetwork",
                              Q_ARG(QString, m_wifiDialogSsid), Q_ARG(QString, password));
}

void SettingsController::connectSavedNetwork(const QString &ssid, int strength,
                                             const QString &security, bool secured) {
    showWifiDialog(ssid, strength, security, secured);
    submitWifiPassword(QString());
}

void SettingsController::showHiddenNetworkDialog() {
    if (!m_wifiDialogHidden) {
        m_wifiDialogSsid.clear();
        m_wifiDialogSecurity = QStringLiteral("wpa-psk");
        m_wifiDialogPassword.clear();
    }
    m_wifiDialogHidden     = true;
    m_wifiDialogConnecting = false;
    m_wifiDialogError.clear();
    m_wifiDialogVisible = true;
    emit wifiDialogChanged();
}

void SettingsController::connectHiddenNetwork(const QString &ssid, const QString &security,
                                              const QString &password) {
    if (!m_networkManager)
        resolveDependencies();
    if (!m_networkManager)
        return;
    m_wifiDialogHidden     = true;
    m_wifiDialogVisible    = true;
    m_wifiDialogSsid       = ssid;
    m_wifiDialogSecurity   = security;
    m_wifiDialogPassword   = password;
    m_wifiDialogConnecting = true;
    m_wifiDialogError.clear();
    emit wifiDialogChanged();
    QMetaObject::invokeMethod(m_networkManager, "connectToHiddenNetwork", Q_ARG(QString, ssid),
                              Q_ARG(QString, security), Q_ARG(QString, password));
}

void SettingsController::showBluetoothDialog(const QString &name, const QString &address,
                                             const QString &type, const QString &mode) {
    m_bluetoothDialogName    = name;
    m_bluetoothDialogAddress = address;
    m_bluetoothDialogType    = type.isEmpty() ? QStringLiteral("device") : type;
    m_bluetoothDialogMode    = mode.isEmpty() ? QStringLiteral("justworks") : mode;
    m_bluetoothDialogPasskey.clear();
    m_bluetoothDialogPairing = false;
    m_bluetoothDialogError.clear();
    setBluetoothDialogVisible(true);
}

void SettingsController::showBluetoothPasskeyConfirmation(const QString &name,
                                                          const QString &address,
                                                          const QString &type, quint32 passkey) {
    m_bluetoothDialogName    = name;
    m_bluetoothDialogAddress = address;
    m_bluetoothDialogType    = type.isEmpty() ? QStringLiteral("device") : type;
    m_bluetoothDialogMode    = QStringLiteral("confirm");
    m_bluetoothDialogPasskey = QString::number(passkey);
    m_bluetoothDialogPairing = false;
    m_bluetoothDialogError.clear();
    setBluetoothDialogVisible(true);
}

void SettingsController::dismissBluetoothDialog() {
    setBluetoothDialogVisible(false);
}

void SettingsController::submitBluetoothPin(const QString &pin) {
    if (!m_bluetoothManager) {
        resolveDependencies();
    }
    if (!m_bluetoothManager) {
        return;
    }
    m_bluetoothDialogPairing = true;
    m_bluetoothDialogError.clear();
    emit bluetoothDialogChanged();
    QMetaObject::invokeMethod(m_bluetoothManager, "pairDevice",
                              Q_ARG(QString, m_bluetoothDialogAddress), Q_ARG(QString, pin));
}

void SettingsController::submitBluetoothPasskey(const QString &passkey) {
    if (!m_bluetoothManager) {
        resolveDependencies();
    }
    if (!m_bluetoothManager) {
        return;
    }
    m_bluetoothDialogPairing = true;
    m_bluetoothDialogError.clear();
    emit bluetoothDialogChanged();
    QMetaObject::invokeMethod(m_bluetoothManager, "pairDevice",
                              Q_ARG(QString, m_bluetoothDialogAddress), Q_ARG(QString, passkey));
}

void SettingsController::confirmBluetoothPairing(bool accepted) {
    if (!m_bluetoothManager) {
        resolveDependencies();
    }
    if (!m_bluetoothManager) {
        return;
    }
    QMetaObject::invokeMethod(m_bluetoothManager, "confirmPairing",
                              Q_ARG(QString, m_bluetoothDialogAddress), Q_ARG(bool, accepted));
    if (!accepted) {
        dismissBluetoothDialog();
    } else {
        m_bluetoothDialogPairing = true;
        emit bluetoothDialogChanged();
    }
}

void SettingsController::cancelBluetoothPairing() {
    if (!m_bluetoothManager) {
        resolveDependencies();
    }
    if (!m_bluetoothManager) {
        return;
    }
    QMetaObject::invokeMethod(m_bluetoothManager, "cancelPairing",
                              Q_ARG(QString, m_bluetoothDialogAddress));
    dismissBluetoothDialog();
}

QString SettingsController::bluetoothPairingModeText(const QString &mode) const {
    if (mode == QLatin1String("pin")) {
        return QStringLiteral("Enter PIN to pair");
    }
    if (mode == QLatin1String("passkey")) {
        return QStringLiteral("Enter passkey displayed on device");
    }
    if (mode == QLatin1String("confirm")) {
        return QStringLiteral("Confirm pairing code");
    }
    return QStringLiteral("Ready to pair");
}

QString SettingsController::bluetoothHelpText(const QString &mode) const {
    if (mode == QLatin1String("pin")) {
        return QStringLiteral("Enter the PIN shown on your device (usually 0000 or 1234)");
    }
    if (mode == QLatin1String("passkey")) {
        return QStringLiteral("Type the 6-digit passkey displayed on the device");
    }
    if (mode == QLatin1String("confirm")) {
        return QStringLiteral("Make sure the code above matches what's shown on your device");
    }
    return QStringLiteral("No PIN required for this device");
}

bool SettingsController::bluetoothCanPair(const QString &mode, const QString &pin,
                                          const QString &passkey) const {
    if (mode == QLatin1String("confirm") || mode == QLatin1String("justworks")) {
        return true;
    }
    if (mode == QLatin1String("pin")) {
        return pin.length() >= 4;
    }
    if (mode == QLatin1String("passkey")) {
        return passkey.length() == 6;
    }
    return false;
}

QString SettingsController::lockoutStatusText(bool lockedOut, int secondsRemaining) const {
    if (lockedOut) {
        return QStringLiteral("Locked (%1s remaining)").arg(std::max(0, secondsRemaining));
    }
    return QStringLiteral("Active");
}

QString SettingsController::quickPinValidationError(const QString &pin,
                                                    const QString &password) const {
    if (pin.length() < 4) {
        return QStringLiteral("PIN must be 4-6 digits");
    }
    if (password.trimmed().isEmpty()) {
        return QStringLiteral("System password required");
    }
    return QString();
}

int SettingsController::notificationAppsRevision() const {
    return m_notificationAppsRevision;
}

QVariantList SettingsController::notificationApps() const {
    QVariantList result;
    if (!m_settingsManager || !m_appSource) {
        const_cast<SettingsController *>(this)->resolveDependencies();
    }
    QAbstractItemModel *model = appModel();
    if (!model || !m_settingsManager)
        return result;

    const QHash<int, QByteArray> roleNames =
        m_roleNames.isEmpty() ? model->roleNames() : m_roleNames;
    auto findRole = [&roleNames](const QByteArray &roleName) {
        for (auto it = roleNames.constBegin(); it != roleNames.constEnd(); ++it) {
            if (it.value() == roleName) {
                return it.key();
            }
        }
        return -1;
    };

    const int idRole   = findRole("id");
    const int nameRole = findRole("name");
    if (idRole == -1 || nameRole == -1) {
        return result;
    }

    const QVariantMap settings = m_settingsManager->property("appNotificationSettings").toMap();
    const int         total    = model->rowCount();
    result.reserve(total);
    for (int i = 0; i < total; ++i) {
        const QModelIndex index   = model->index(i, 0);
        const QString     id      = model->data(index, idRole).toString();
        const QString     name    = model->data(index, nameRole).toString();
        const bool        enabled = settings.value(id, true).toBool();
        QVariantMap       entry;
        entry.insert("id", id);
        entry.insert("name", name);
        entry.insert("enabled", enabled);
        result.append(entry);
    }
    return result;
}

QString SettingsController::osVersion() const {
    return m_osVersion;
}

QString SettingsController::kernelVersion() const {
    return m_kernelVersion;
}

QString SettingsController::deviceModel() const {
    return m_deviceModel;
}

QString SettingsController::displayResolution() const {
    return m_displayResolution;
}

QString SettingsController::displayRefreshRate() const {
    return m_displayRefreshRate;
}

QString SettingsController::displayDpi() const {
    return m_displayDpi;
}

QString SettingsController::displayScale() const {
    return m_displayScale;
}

QVariantList SettingsController::openSourceLicenses() const {
    return m_openSourceLicenses;
}

bool SettingsController::wifiDialogVisible() const {
    return m_wifiDialogVisible;
}

QString SettingsController::wifiDialogSsid() const {
    return m_wifiDialogSsid;
}

int SettingsController::wifiDialogStrength() const {
    return m_wifiDialogStrength;
}

QString SettingsController::wifiDialogSecurity() const {
    return m_wifiDialogSecurity;
}

bool SettingsController::wifiDialogSecured() const {
    return m_wifiDialogSecured;
}

bool SettingsController::wifiDialogConnecting() const {
    return m_wifiDialogConnecting;
}

QString SettingsController::wifiDialogError() const {
    return m_wifiDialogError;
}

QString SettingsController::wifiDialogPassword() const {
    return m_wifiDialogPassword;
}

bool SettingsController::wifiDialogHidden() const {
    return m_wifiDialogHidden;
}

bool SettingsController::bluetoothDialogVisible() const {
    return m_bluetoothDialogVisible;
}

QString SettingsController::bluetoothDialogName() const {
    return m_bluetoothDialogName;
}

QString SettingsController::bluetoothDialogAddress() const {
    return m_bluetoothDialogAddress;
}

QString SettingsController::bluetoothDialogType() const {
    return m_bluetoothDialogType;
}

QString SettingsController::bluetoothDialogMode() const {
    return m_bluetoothDialogMode;
}

QString SettingsController::bluetoothDialogPasskey() const {
    return m_bluetoothDialogPasskey;
}

bool SettingsController::bluetoothDialogPairing() const {
    return m_bluetoothDialogPairing;
}

QString SettingsController::bluetoothDialogError() const {
    return m_bluetoothDialogError;
}

void SettingsController::resolveDependencies() {
    QQmlEngine *engine = qmlEngine(this);
    if (!engine) {
        return;
    }
    QQmlContext *context = engine->rootContext();
    if (!context) {
        return;
    }

    if (!m_settingsManager) {
        m_settingsManager = context->contextProperty("SettingsManagerCpp").value<QObject *>();
        if (m_settingsManager) {
            const int notifyIndex =
                m_settingsManager->metaObject()->indexOfSignal("appNotificationSettingsChanged()");
            const int notifySlot = metaObject()->indexOfSlot("handleNotificationSettingsChanged()");
            if (notifyIndex != -1 && notifySlot != -1) {
                QMetaObject::connect(m_settingsManager, notifyIndex, this, notifySlot);
            }
        }
    }

    if (!m_appSource) {
        QObject *registry = context->contextProperty("MarathonAppRegistry").value<QObject *>();
        if (registry) {
            m_appSource = registry;
        } else {
            m_appSource = context->contextProperty("AppModel").value<QObject *>();
        }
    }

    if (!m_networkManager) {
        m_networkManager = context->contextProperty("NetworkManagerCpp").value<QObject *>();
        if (m_networkManager) {
            const QMetaObject *meta    = m_networkManager->metaObject();
            const int          success = meta->indexOfSignal("connectionSuccess()");
            const int          failed  = meta->indexOfSignal("connectionFailed(QString)");
            if (success != -1) {
                QMetaObject::connect(m_networkManager, success, this,
                                     metaObject()->indexOfSlot("handleWifiConnectionSuccess()"));
            }
            if (failed != -1) {
                QMetaObject::connect(
                    m_networkManager, failed, this,
                    metaObject()->indexOfSlot("handleWifiConnectionFailed(QString)"));
            }
        }
    }

    if (!m_bluetoothManager) {
        m_bluetoothManager = context->contextProperty("BluetoothManagerCpp").value<QObject *>();
        if (m_bluetoothManager) {
            const QMetaObject *meta    = m_bluetoothManager->metaObject();
            const int          paired  = meta->indexOfSignal("pairingSucceeded(QString)");
            const int          failed  = meta->indexOfSignal("pairingFailed(QString,QString)");
            const int          pin     = meta->indexOfSignal("pinRequested(QString,QString)");
            const int          passkey = meta->indexOfSignal("passkeyRequested(QString,QString)");
            const int confirm = meta->indexOfSignal("passkeyConfirmation(QString,QString,quint32)");
            if (paired != -1) {
                QMetaObject::connect(
                    m_bluetoothManager, paired, this,
                    metaObject()->indexOfSlot("handleBluetoothPairingSucceeded(QString)"));
            }
            if (failed != -1) {
                QMetaObject::connect(
                    m_bluetoothManager, failed, this,
                    metaObject()->indexOfSlot("handleBluetoothPairingFailed(QString,QString)"));
            }
            if (pin != -1) {
                QMetaObject::connect(
                    m_bluetoothManager, pin, this,
                    metaObject()->indexOfSlot("handleBluetoothPinRequested(QString,QString)"));
            }
            if (passkey != -1) {
                QMetaObject::connect(
                    m_bluetoothManager, passkey, this,
                    metaObject()->indexOfSlot("handleBluetoothPasskeyRequested(QString,QString)"));
            }
            if (confirm != -1) {
                QMetaObject::connect(
                    m_bluetoothManager, confirm, this,
                    metaObject()->indexOfSlot(
                        "handleBluetoothPasskeyConfirmation(QString,QString,quint32)"));
            }
        }
    }

    QAbstractItemModel *model = appModel();
    if (model) {
        m_roleNames = model->roleNames();
        connect(model, &QAbstractItemModel::modelReset, this,
                &SettingsController::handleAppSourceChanged);
        connect(model, &QAbstractItemModel::rowsInserted, this,
                &SettingsController::handleAppSourceChanged);
        connect(model, &QAbstractItemModel::rowsRemoved, this,
                &SettingsController::handleAppSourceChanged);
        connect(model, &QAbstractItemModel::dataChanged, this,
                &SettingsController::handleAppSourceChanged);
    }
}

QAbstractItemModel *SettingsController::appModel() const {
    return qobject_cast<QAbstractItemModel *>(m_appSource.data());
}

void SettingsController::handleAppSourceChanged() {
    ++m_notificationAppsRevision;
    emit notificationAppsChanged();
}

void SettingsController::handleNotificationSettingsChanged() {
    ++m_notificationAppsRevision;
    emit notificationAppsChanged();
}

void SettingsController::updateSystemInfo() {
    const QString pretty = QSysInfo::prettyProductName();
    const QString osVer  = QOperatingSystemVersion::current().name() + " " +
        QOperatingSystemVersion::current().version().toString();
    m_osVersion = pretty.isEmpty() ? osVer : pretty;
    m_kernelVersion =
        QStringLiteral("%1 %2").arg(QSysInfo::kernelType(), QSysInfo::kernelVersion());

    QString           model;
    const QStringList modelFiles = {QStringLiteral("/sys/devices/virtual/dmi/id/product_name"),
                                    QStringLiteral("/sys/firmware/devicetree/base/model")};
    for (const QString &path : modelFiles) {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
            continue;
        model = QString::fromUtf8(f.readAll()).trimmed();
        if (!model.isEmpty())
            break;
    }
    if (model.isEmpty())
        model = QSysInfo::machineHostName();
    if (model.isEmpty())
        model = QSysInfo::currentCpuArchitecture();
    m_deviceModel = model;

    QScreen *screen = QGuiApplication::primaryScreen();
    if (screen) {
        const QSize size     = screen->size();
        m_displayResolution  = QStringLiteral("%1x%2").arg(size.width()).arg(size.height());
        m_displayRefreshRate = QString::number(screen->refreshRate(), 'f', 0) + " Hz";
        m_displayDpi         = QString::number(screen->physicalDotsPerInch(), 'f', 0) + " dpi";
        m_displayScale       = QString::number(screen->devicePixelRatio(), 'f', 2);
    } else {
        m_displayResolution.clear();
        m_displayRefreshRate.clear();
        m_displayDpi.clear();
        m_displayScale.clear();
    }

    emit systemInfoChanged();
}

void SettingsController::handleWifiConnectionSuccess() {
    m_wifiDialogConnecting = false;
    m_wifiDialogError.clear();
    m_wifiDialogPassword.clear();
    m_wifiDialogHidden = false;
    setWifiDialogVisible(false);
}

void SettingsController::handleWifiConnectionFailed(const QString &message) {
    m_wifiDialogConnecting = false;
    setWifiDialogError(message);
}

void SettingsController::handleBluetoothPairingSucceeded(const QString &) {
    m_bluetoothDialogPairing = false;
    m_bluetoothDialogError.clear();
    setBluetoothDialogVisible(false);
}

void SettingsController::handleBluetoothPairingFailed(const QString &, const QString &error) {
    m_bluetoothDialogPairing = false;
    setBluetoothDialogError(error);
}

void SettingsController::handleBluetoothPinRequested(const QString &address, const QString &name) {
    showBluetoothDialog(name, address, QStringLiteral("device"), QStringLiteral("pin"));
}

void SettingsController::handleBluetoothPasskeyRequested(const QString &address,
                                                         const QString &name) {
    showBluetoothDialog(name, address, QStringLiteral("device"), QStringLiteral("passkey"));
}

void SettingsController::handleBluetoothPasskeyConfirmation(const QString &address,
                                                            const QString &name, quint32 passkey) {
    showBluetoothPasskeyConfirmation(name, address, QStringLiteral("device"), passkey);
}

void SettingsController::setWifiDialogVisible(bool visible) {
    if (m_wifiDialogVisible == visible) {
        return;
    }
    m_wifiDialogVisible = visible;
    emit wifiDialogChanged();
}

void SettingsController::setWifiDialogError(const QString &message) {
    m_wifiDialogError = message;
    emit wifiDialogChanged();
}

void SettingsController::setBluetoothDialogVisible(bool visible) {
    if (m_bluetoothDialogVisible == visible) {
        return;
    }
    m_bluetoothDialogVisible = visible;
    emit bluetoothDialogChanged();
}

void SettingsController::setBluetoothDialogError(const QString &message) {
    m_bluetoothDialogError = message;
    emit bluetoothDialogChanged();
}
