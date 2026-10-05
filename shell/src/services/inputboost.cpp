#include "inputboost.h"

#include <QDebug>
#include <QDir>
#include <QEvent>
#include <QFile>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <utility>

namespace {
    // Covers the settle or fling animation after a release and an app's
    // first frames after a launch tap.
    constexpr int kHoldMs = 1500;

    QByteArray readValue(const QString &path) {
        QFile f(path);
        if (!f.open(QIODevice::ReadOnly))
            return {};
        return f.readAll().trimmed();
    }
} // namespace

InputBoost::InputBoost(QObject *parent)
    : QObject(parent) {
    const QDir        base(QStringLiteral("/sys/devices/system/cpu/cpufreq"));
    const QStringList policies =
        base.entryList(QStringList() << QStringLiteral("policy*"), QDir::Dirs);
    for (const QString &name : policies) {
        const QString    dir     = base.filePath(name);
        const QByteArray maxFreq = readValue(dir + QStringLiteral("/cpuinfo_max_freq"));
        const QByteArray minFreq = readValue(dir + QStringLiteral("/scaling_min_freq"));
        if (maxFreq.isEmpty() || minFreq.isEmpty())
            continue;
        const QByteArray path = QFile::encodeName(dir + QStringLiteral("/scaling_min_freq"));
        const int        fd   = ::open(path.constData(), O_WRONLY | O_CLOEXEC);
        if (fd < 0) {
            qWarning() << "[InputBoost] Cannot open" << path << strerror(errno)
                       << "- interaction boost disabled for this policy";
            continue;
        }
        m_policies.append({fd, maxFreq, minFreq});
    }

    m_release.setSingleShot(true);
    m_release.setInterval(kHoldMs);
    connect(&m_release, &QTimer::timeout, this, [this] { write(false); });
}

InputBoost::~InputBoost() {
    if (m_boosted)
        write(false);
    for (const Policy &p : std::as_const(m_policies))
        ::close(p.fd);
}

void InputBoost::boost() {
    if (m_policies.isEmpty())
        return;
    if (!m_boosted)
        write(true);
    m_release.start();
}

bool InputBoost::eventFilter(QObject *watched, QEvent *event) {
    // Input reaches the window first, then each item it is delivered to;
    // the window is enough.
    if (!watched->isWindowType())
        return QObject::eventFilter(watched, event);
    switch (event->type()) {
        case QEvent::TouchBegin:
        case QEvent::TouchUpdate:
        case QEvent::MouseButtonPress:
        case QEvent::MouseMove:
        case QEvent::Wheel:
        case QEvent::KeyPress: boost(); break;
        default: break;
    }
    return QObject::eventFilter(watched, event);
}

void InputBoost::write(bool boosted) {
    m_boosted = boosted;
    for (const Policy &p : std::as_const(m_policies)) {
        const QByteArray &value = boosted ? p.boostFreq : p.restingFreq;
        if (::pwrite(p.fd, value.constData(), value.size(), 0) < 0)
            qWarning() << "[InputBoost] scaling_min_freq write failed:" << strerror(errno);
    }
}
