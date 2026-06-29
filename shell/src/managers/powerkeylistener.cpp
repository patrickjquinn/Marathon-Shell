#include "powerkeylistener.h"

#include <QDebug>
#include <QFile>
#include <QSocketNotifier>
#include <QStringList>

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <linux/input.h>
#include <sys/types.h>
#include <unistd.h>

namespace {

    // Section A2: loud failure is preferred to silent swallow. Open errors are
    // logged with errno so a future image regression (e.g. user dropped from the
    // "input" group) is visible in the journal on first boot, not at first press.
    constexpr int kKeyPower = KEY_POWER;

    // /proc/bus/input/devices reports KEY bits as a space-separated list of
    // uppercase hex words, lowest-order word last. Parse that into a 64-bit
    // chunk vector so we can test bit 116 (== KEY_POWER) directly.
    bool deviceAdvertisesKey(const QStringList &hexWords, int code) {
        if (hexWords.isEmpty())
            return false;

        const int wordIndex = code / 64;
        const int bit       = code % 64;

        // hexWords[0] is the highest-order chunk. Map "code" → index from the
        // *right* end of the list.
        const int idxFromRight = wordIndex;
        const int idx          = hexWords.size() - 1 - idxFromRight;
        if (idx < 0)
            return false;

        bool       ok   = false;
        const auto word = hexWords.at(idx).toULongLong(&ok, 16);
        if (!ok)
            return false;
        return (word & (1ULL << bit)) != 0;
    }

} // namespace

PowerKeyListener::PowerKeyListener(QObject *parent)
    : QObject(parent) {
    const QStringList devices = discoverPowerKeyDevices();
    if (devices.isEmpty()) {
        qWarning() << "[PowerKeyListener] No input device advertises KEY_POWER. "
                      "The power button will not wake the display.";
        return;
    }

    for (const QString &path : devices) {
        if (openDevice(path)) {
            qInfo() << "[PowerKeyListener] Watching" << path << "for KEY_POWER";
        }
    }

    if (m_watches.isEmpty()) {
        qWarning() << "[PowerKeyListener] Found" << devices.size()
                   << "candidate device(s) but failed to open any. "
                      "Check that the shell user is in the 'input' group.";
    }
}

PowerKeyListener::~PowerKeyListener() {
    closeAll();
}

QStringList PowerKeyListener::discoverPowerKeyDevices() const {
    QFile f("/proc/bus/input/devices");
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[PowerKeyListener] Cannot open /proc/bus/input/devices:" << f.errorString();
        return {};
    }

    QStringList result;
    QString     name;
    QString     handler;
    QStringList keyWords;

    auto        flush = [&]() {
        if (handler.isEmpty()) {
            name.clear();
            handler.clear();
            keyWords.clear();
            return;
        }
        const bool advertises = deviceAdvertisesKey(keyWords, kKeyPower);
        qWarning() << "[PowerKeyListener] scan:" << name << handler << "keyWords=" << keyWords
                   << "advertisesPower=" << advertises;
        if (advertises) {
            const QString path = QStringLiteral("/dev/input/") + handler;
            result.append(path);
        }
        name.clear();
        handler.clear();
        keyWords.clear();
    };

    // QTextStream::atEnd() consults QIODevice::size(), which is 0 for /proc
    // virtual files even though they stream content. The earlier version
    // bailed on the very first iteration and reported "no input device
    // advertises KEY_POWER" on every boot, leaving the shell unable to
    // observe power-button presses. readAll() works because QFile drains
    // the device until read() returns 0.
    const QString content = QString::fromUtf8(f.readAll());
    f.close();
    const QStringList lines = content.split(QLatin1Char('\n'));
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        if (line.isEmpty()) {
            flush();
            continue;
        }
        if (line.startsWith(QLatin1String("N: Name="))) {
            name = line.mid(8).trimmed();
            if (name.startsWith(QLatin1Char('"')) && name.endsWith(QLatin1Char('"')))
                name = name.mid(1, name.size() - 2);
        } else if (line.startsWith(QLatin1String("H: Handlers="))) {
            const QStringList tokens = line.mid(12).split(QLatin1Char(' '), Qt::SkipEmptyParts);
            for (const QString &t : tokens) {
                if (t.startsWith(QLatin1String("event"))) {
                    handler = t;
                    break;
                }
            }
        } else if (line.startsWith(QLatin1String("B: KEY="))) {
            keyWords = line.mid(7).split(QLatin1Char(' '), Qt::SkipEmptyParts);
        }
    }
    flush();
    return result;
}

bool PowerKeyListener::openDevice(const QString &path) {
    const int fd = ::open(path.toLocal8Bit().constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        qWarning() << "[PowerKeyListener] open(" << path << ") failed:" << ::strerror(errno);
        return false;
    }

    auto *notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
    connect(notifier, &QSocketNotifier::activated, this, &PowerKeyListener::onFdReadable);

    Watch w{fd, QString(), path, notifier};
    m_watches.append(w);
    return true;
}

void PowerKeyListener::closeAll() {
    for (Watch &w : m_watches) {
        if (w.notifier) {
            w.notifier->setEnabled(false);
            w.notifier->deleteLater();
            w.notifier = nullptr;
        }
        if (w.fd >= 0) {
            ::close(w.fd);
            w.fd = -1;
        }
    }
    m_watches.clear();
}

void PowerKeyListener::onFdReadable(int fd) {
    struct input_event ev{};
    while (true) {
        const ssize_t n = ::read(fd, &ev, sizeof(ev));
        if (n == (ssize_t)sizeof(ev)) {
            if (ev.type == EV_KEY && ev.code == kKeyPower) {
                if (ev.value == 1) {
                    qInfo() << "[PowerKeyListener] KEY_POWER down on fd" << fd;
                    emit powerKeyPressed();
                } else if (ev.value == 0) {
                    emit powerKeyReleased();
                }
            }
            continue;
        }
        if (n < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK)
                break;
            if (errno == EINTR)
                continue;
            qWarning() << "[PowerKeyListener] read(fd=" << fd << ") error:" << ::strerror(errno);
            break;
        }
        // Short read shouldn't happen for input_event; treat as EOF.
        qWarning() << "[PowerKeyListener] short read on fd" << fd << ":" << n << "bytes";
        break;
    }
}
