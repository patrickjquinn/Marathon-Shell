#include "keelhost.h"

#include <QDBusServer>
#include <QEvent>
#include <QRegularExpression>

using namespace Qt::StringLiterals;

static constexpr auto kPath     = "/org/shipwright/keel/Shell"_L1;
static constexpr auto kThemeDir = "/desktop/jolla/theme/"_L1;

KeelHost::KeelHost(int dpi, QObject *parent)
    : QObject(parent)
    , m_dpi(dpi) {}

bool KeelHost::start(const QString &runtimeDir) {
    // unix:dir picks a fresh socket name and the server unlinks it on exit;
    // a per-PID directory would collide (every sandboxed runner is PID 2).
    m_server = new QDBusServer(QStringLiteral("unix:dir=") + runtimeDir, this);
    if (!m_server->isConnected())
        return false;
    connect(m_server, &QDBusServer::newConnection, this, [this](const QDBusConnection &c) {
        QDBusConnection conn(c);
        conn.registerObject(kPath, this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals |
                                QDBusConnection::ExportAllProperties);
        m_peers.append(conn);
    });
    return true;
}

QString KeelHost::address() const {
    return m_server ? m_server->address() : QString();
}

QHash<QString, QString> KeelHost::environment() const {
    QHash<QString, QString> env{
        {QStringLiteral("KEEL_SHELL"), QStringLiteral("1")},
        {QStringLiteral("KEEL_SHELL_PROTOCOL"), QStringLiteral("1")},
        {QStringLiteral("KEEL_SHELL_DBUS"), address()},
        {QStringLiteral("KEEL_SHELL_COVER_TITLE"), QStringLiteral("keel:cover")},
        {QStringLiteral("KEEL_SHELL_COVER_ENABLED"), QStringLiteral("1")},
        {QStringLiteral("KEEL_SHELL_DPI"), QString::number(m_dpi)},
    };
    static const QRegularExpression nonAlnum(QStringLiteral("[^A-Z0-9]"));
    QStringList                     keys;
    for (auto it = m_ambience.cbegin(); it != m_ambience.cend(); ++it) {
        if (!it.key().startsWith(kThemeDir))
            continue;
        QString name = it.key().mid(kThemeDir.size()).toUpper();
        name.replace(nonAlnum, QStringLiteral("_"));
        env.insert(QStringLiteral("KEEL_AMBIENCE_") + name, it.value().toString());
        keys << it.key();
    }
    if (!keys.isEmpty())
        env.insert(QStringLiteral("KEEL_AMBIENCE_KEYS"), keys.join(QLatin1Char(':')));
    return env;
}

void KeelHost::setAmbience(const QVariantMap &ambience) {
    if (ambience == m_ambience)
        return;
    m_ambience = ambience;
    emit AmbienceChanged(m_ambience);
}

void KeelHost::setActive(bool active) {
    if (active == m_active)
        return;
    m_active = active;
    emit ActiveChanged(m_active);
}

void KeelHost::setCoverStatus(int status) {
    if (status == m_coverStatus)
        return;
    m_coverStatus = status;
    emit CoverStatusChanged(m_coverStatus);
}

void KeelHost::requestClose() {
    emit CloseRequested();
}

QString KeelHost::Ping() {
    return QStringLiteral("marathon");
}

QVariantMap KeelHost::GetAmbience() {
    return m_ambience;
}

void KeelHost::Activate() const {
    if (onActivate)
        onActivate();
}

void KeelHost::SetContentOrientation(int degrees) {
    if (degrees == m_contentOrientation)
        return;
    m_contentOrientation = degrees;
    emit ContentOrientationChanged(degrees);
}

bool KeelCloseGuard::eventFilter(QObject *watched, QEvent *event) {
    if (event->type() != QEvent::Close || m_closing)
        return QObject::eventFilter(watched, event);
    m_closing = true;
    event->ignore();
    m_onFirstClose();
    return true;
}
