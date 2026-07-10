#include "deviceprofile.h"

#include <QByteArray>
#include <QDebug>
#include <QFile>
#include <QHash>
#include <QStringList>
#include <QTextStream>

namespace {

// A parsed KEY=VALUE map plus a resolver that layers env override on top.
struct ConfMap {
    QHash<QString, QString> kv;

    // Value for KEY: env var `env` wins if set; else conf file; else the
    // caller's default (kept in the field initialiser). Returns whether a
    // source provided a value, and the string in `out`.
    bool value(const char *env, const QString &key, QString &out) const {
        const QByteArray e = qgetenv(env);
        if (!e.isEmpty()) {
            out = QString::fromUtf8(e);
            return true;
        }
        auto it = kv.constFind(key);
        if (it != kv.constEnd()) {
            out = it.value();
            return true;
        }
        return false;
    }
};

ConfMap parseConf() {
    ConfMap m;
    QString path = QString::fromUtf8(qgetenv("MARATHON_DEVICE_PROFILE"));
    if (path.isEmpty())
        path = QStringLiteral("/etc/marathon/device-profile.conf");

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text))
        return m; // missing → all built-in defaults

    QTextStream in(&f);
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty() || line.startsWith('#'))
            continue;
        const int eq = line.indexOf('=');
        if (eq <= 0)
            continue;
        QString key = line.left(eq).trimmed();
        QString val = line.mid(eq + 1).trimmed();
        // strip an optional surrounding pair of quotes
        if (val.size() >= 2 && (val.front() == '"' || val.front() == '\'') && val.back() == val.front())
            val = val.mid(1, val.size() - 2);
        m.kv.insert(key, val);
    }
    return m;
}

bool toBool(const QString &s, bool fallback) {
    const QString v = s.trimmed().toLower();
    if (v == "1" || v == "true" || v == "yes" || v == "on")
        return true;
    if (v == "0" || v == "false" || v == "no" || v == "off")
        return false;
    return fallback;
}

} // namespace

DeviceProfile &DeviceProfile::instance() {
    static DeviceProfile inst;
    return inst;
}

DeviceProfile::DeviceProfile(QObject *parent) : QObject(parent) {
    load();
}

void DeviceProfile::load() {
    const ConfMap conf = parseConf();
    QString       s;

    if (conf.value("MARATHON_DEVICE_ID", QStringLiteral("DEVICE_ID"), s))
        m_deviceId = s;
    if (conf.value("MARATHON_GPU_STACK", QStringLiteral("GPU_STACK"), s))
        m_gpuStack = s;

    // GLES level as "MAJOR.MINOR" (e.g. "2.0", "3.0"). Env MARATHON_GLES_VERSION
    // overrides the conf GLES_LEVEL.
    if (conf.value("MARATHON_GLES_VERSION", QStringLiteral("GLES_LEVEL"), s)) {
        const QStringList parts = s.split('.');
        bool              okMaj = false;
        const int         maj   = parts.value(0).toInt(&okMaj);
        if (okMaj && maj > 0) {
            m_glesMajor = maj;
            m_glesMinor = parts.size() > 1 ? parts.value(1).toInt() : 0;
        }
    }

    if (conf.value("MARATHON_SURFACE_ALPHA", QStringLiteral("SURFACE_ALPHA"), s))
        m_surfaceHasAlpha = toBool(s, m_surfaceHasAlpha);

    // GPU_MSAA is the hardware's max FBO sample count (0 = none). Reuses the
    // long-standing MARATHON_LAYER_SAMPLES env as the override so existing
    // deployments keep working.
    if (conf.value("MARATHON_LAYER_SAMPLES", QStringLiteral("GPU_MSAA"), s)) {
        bool      ok = false;
        const int n  = s.toInt(&ok);
        if (ok)
            m_hwMsaaSamples = n;
    }

    if (conf.value("MARATHON_GPU_HDR", QStringLiteral("GPU_RGBA16F"), s))
        m_gpuRgba16f = toBool(s, m_gpuRgba16f);

    if (conf.value("MARATHON_RENDER_NODE", QStringLiteral("RENDER_NODE"), s))
        m_renderNode = s;
    if (conf.value("MARATHON_CPU_GOVERNOR", QStringLiteral("CPU_GOVERNOR"), s))
        m_cpuGovernor = s;

    if (conf.value("MARATHON_BRIGHTNESS_FLOOR", QStringLiteral("BRIGHTNESS_FLOOR"), s)) {
        bool        ok = false;
        const qreal v  = s.toDouble(&ok);
        if (ok && v >= 0.0 && v <= 1.0)
            m_brightnessFloor = v;
    }

    // Runner canvas. Env keys reuse MARATHON_APP_WIDTH/HEIGHT — the same names
    // the app-runner already reads — so a value set in the shell's env flows
    // straight through to the runner unchanged.
    if (conf.value("MARATHON_APP_WIDTH", QStringLiteral("RUNNER_WIDTH"), s)) {
        bool      ok = false;
        const int n  = s.toInt(&ok);
        if (ok && n > 0)
            m_runnerWidth = n;
    }
    if (conf.value("MARATHON_APP_HEIGHT", QStringLiteral("RUNNER_HEIGHT"), s)) {
        bool      ok = false;
        const int n  = s.toInt(&ok);
        if (ok && n > 0)
            m_runnerHeight = n;
    }

    qInfo().noquote() << "[DeviceProfile] id=" << m_deviceId << "gpu=" << m_gpuStack
                      << QStringLiteral("gles=%1.%2").arg(m_glesMajor).arg(m_glesMinor)
                      << "alpha=" << m_surfaceHasAlpha << "msaa=" << m_hwMsaaSamples
                      << "renderNode=" << m_renderNode << "gov=" << m_cpuGovernor
                      << QStringLiteral("runner=%1x%2").arg(m_runnerWidth).arg(m_runnerHeight);
}
