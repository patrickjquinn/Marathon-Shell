#include "drmmasterwait.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThread>

#include <algorithm>
#include <fcntl.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

QString kmsConfigDevice(const QString &configPath) {
    QFile f(configPath);
    if (configPath.isEmpty() || !f.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(f.readAll()).object().value(QStringLiteral("device")).toString();
}

static int openCard(const QString &card) {
    return ::open(QFile::encodeName(card).constData(), O_RDWR | O_CLOEXEC);
}

QStringList eglfsKmsCards() {
    const QString configured = kmsConfigDevice(qEnvironmentVariable("QT_QPA_EGLFS_KMS_CONFIG"));
    if (!configured.isEmpty())
        return {configured};

    QStringList       cards;
    const QDir        dri(QStringLiteral("/dev/dri"));
    const QStringList nodes = dri.entryList({QStringLiteral("card*")}, QDir::System, QDir::Name);
    for (const QString &node : nodes) {
        const QString path = dri.filePath(node);
        const int     fd   = openCard(path);
        if (fd < 0)
            continue;
        if (drmModeRes *res = drmModeGetResources(fd)) {
            if (res->count_connectors > 0)
                cards << path;
            drmModeFreeResources(res);
        }
        ::close(fd);
    }
    return cards;
}

// Our own open is made master exactly when nobody else holds it.
static bool heldByOther(const QString &card) {
    const int fd = openCard(card);
    if (fd < 0)
        return false;
    const bool held = !drmIsMaster(fd);
    ::close(fd);
    return held;
}

int waitForDrmMaster(const QStringList &cards, int timeoutMs) {
    if (std::none_of(cards.cbegin(), cards.cend(), heldByOther))
        return 0;
    QElapsedTimer waited;
    waited.start();
    do {
        if (waited.elapsed() >= timeoutMs)
            return -1;
        QThread::msleep(100);
    } while (std::any_of(cards.cbegin(), cards.cend(), heldByOther));
    return static_cast<int>(waited.elapsed());
}
