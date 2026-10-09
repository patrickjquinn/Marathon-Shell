// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "trackersource.h"

#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QFileInfo>
#include <QUrl>
#include <QtEndian>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <unistd.h>

namespace keel::pickers {

namespace {

constexpr int kReadTimeoutMs = 30000;

qint32 hostInt32(const char *p)
{
    qint32 v = 0;
    std::memcpy(&v, p, sizeof v);
    return v;
}

// Reads `fd` until EOF, or until `done` says the endpoint replied and the
// pipe is drained: the endpoint writes every row before it replies, but the
// pending call keeps a copy of the pipe's write end, so EOF does not come
// until the call is gone.
template<typename Done>
bool readAll(int fd, const Done &done, QByteArray *out, QString *error)
{
    char buf[16384];
    int waited = 0;
    for (;;) {
        pollfd pfd {};
        pfd.fd = fd;
        pfd.events = POLLIN;
        const int ready = ::poll(&pfd, 1, 50);
        if (ready < 0 && errno == EINTR)
            continue;
        if (ready < 0) {
            *error = QString::fromLocal8Bit(std::strerror(errno));
            return false;
        }
        if (ready == 0) {
            if (done()) {
                // Everything was written before the reply: drain what the
                // last poll may have missed, without blocking.
                ::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK);
                ssize_t n = 0;
                while ((n = ::read(fd, buf, sizeof buf)) > 0)
                    out->append(buf, n);
                return true;
            }
            waited += 50;
            if (waited >= kReadTimeoutMs) {
                *error = QStringLiteral("Tracker did not answer in time");
                return false;
            }
            continue;
        }
        const ssize_t n = ::read(fd, buf, sizeof buf);
        if (n < 0 && (errno == EINTR || errno == EAGAIN))
            continue;
        if (n < 0) {
            *error = QString::fromLocal8Bit(std::strerror(errno));
            return false;
        }
        if (n == 0)
            return true;
        out->append(buf, n);
    }
}

QString classFor(Category category)
{
    switch (category) {
    case Category::Image:
        return QStringLiteral("nfo:Image");
    case Category::Video:
        return QStringLiteral("nfo:Video");
    case Category::Music:
        return QStringLiteral("nmm:MusicPiece");
    case Category::Document:
        return QStringLiteral("nfo:Document");
    case Category::Any:
    case Category::Download:
    case Category::File:
        break;
    }
    return {};
}

} // namespace

QString TrackerSource::service()
{
    const QString s = qEnvironmentVariable("KEEL_PICKERS_TRACKER_SERVICE");
    return s.isEmpty() ? QStringLiteral("org.freedesktop.Tracker3.Miner.Files") : s;
}

QString TrackerSource::objectPath()
{
    return QStringLiteral("/org/freedesktop/Tracker3/Endpoint");
}

QString TrackerSource::interfaceName()
{
    return QStringLiteral("org.freedesktop.Tracker3.Endpoint");
}

bool TrackerSource::available()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() || !(bus.connectionCapabilities() & QDBusConnection::UnixFileDescriptorPassing))
        return false;
    QDBusConnectionInterface *iface = bus.interface();
    if (!iface)
        return false;
    if (iface->isServiceRegistered(service()).value())
        return true;
    return iface->activatableServiceNames().value().contains(service());
}

QString TrackerSource::queryFor(Category category, int limit)
{
    const QString cls = classFor(category);
    if (cls.isEmpty())
        return {};
    // Tracker 3 predefines the nie, nfo and nmm prefixes. The content
    // resource (?c) is stored as a file data object (?f) that has the URL.
    return QStringLiteral("SELECT ?url ?mime ?title ?size ?modified WHERE { "
                          "?c a %1 ; nie:isStoredAs ?f . "
                          "?f nie:url ?url . "
                          "OPTIONAL { ?c nie:mimeType ?mime } "
                          "OPTIONAL { ?c nie:title ?title } "
                          "OPTIONAL { ?f nfo:fileSize ?size } "
                          "OPTIONAL { ?f nfo:fileLastModified ?modified } "
                          "FILTER (STRSTARTS(?url, \"file://\")) "
                          "} ORDER BY DESC(?modified) LIMIT %2")
        .arg(cls)
        .arg(limit);
}

bool TrackerSource::parseCursor(const QByteArray &data, QList<QStringList> *rows, QString *error)
{
    qsizetype pos = 0;
    const qsizetype size = data.size();
    while (pos < size) {
        if (size - pos < 4) {
            *error = QStringLiteral("truncated row header");
            return false;
        }
        const qint32 columns = hostInt32(data.constData() + pos);
        pos += 4;
        if (columns <= 0 || columns > 1024 || size - pos < static_cast<qsizetype>(columns) * 8) {
            *error = QStringLiteral("bad column count");
            return false;
        }
        pos += static_cast<qsizetype>(columns) * 4; // value types: every value comes as text
        QList<qint32> offsets;
        offsets.reserve(columns);
        for (qint32 i = 0; i < columns; ++i) {
            offsets.append(hostInt32(data.constData() + pos));
            pos += 4;
        }
        for (qint32 i = 0; i < columns; ++i) {
            const qint32 start = i == 0 ? 0 : offsets.at(i - 1) + 1;
            if (offsets.at(i) < start - 1 || (i > 0 && offsets.at(i) < offsets.at(i - 1))) {
                *error = QStringLiteral("bad value offsets");
                return false;
            }
        }
        const qsizetype rowLength = static_cast<qsizetype>(offsets.last()) + 1;
        if (size - pos < rowLength) {
            *error = QStringLiteral("truncated row data");
            return false;
        }
        QStringList row;
        row.reserve(columns);
        for (qint32 i = 0; i < columns; ++i) {
            const qint32 start = i == 0 ? 0 : offsets.at(i - 1) + 1;
            row.append(QString::fromUtf8(data.constData() + pos + start, offsets.at(i) - start));
        }
        rows->append(row);
        pos += rowLength;
    }
    return true;
}

bool TrackerSource::query(const QString &sparql, QList<QStringList> *rows, QString *error)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        *error = QStringLiteral("no session bus");
        return false;
    }
    int fds[2] = { -1, -1 };
    if (::pipe2(fds, O_CLOEXEC) != 0) {
        *error = QString::fromLocal8Bit(std::strerror(errno));
        return false;
    }
    QDBusMessage call = QDBusMessage::createMethodCall(service(), objectPath(), interfaceName(),
                                                       QStringLiteral("Query"));
    // QDBusUnixFileDescriptor keeps its own duplicate; ours closes now so
    // that EOF arrives when the endpoint closes its copy.
    call << sparql << QVariant::fromValue(QDBusUnixFileDescriptor(fds[1])) << QVariantMap();
    ::close(fds[1]);
    QDBusPendingCall pending = bus.asyncCall(call, kReadTimeoutMs);
    call = QDBusMessage();

    QByteArray data;
    const bool read = readAll(fds[0], [&pending]() { return pending.isFinished(); }, &data, error);
    ::close(fds[0]);
    pending.waitForFinished();
    if (pending.isError()) {
        *error = pending.error().message();
        return false;
    }
    if (!read)
        return false;
    return parseCursor(data, rows, error);
}

bool TrackerSource::fetch(Category category, int limit, QList<ContentItem> *items, QString *error)
{
    const QString sparql = queryFor(category, limit);
    if (sparql.isEmpty()) {
        *error = QStringLiteral("no Tracker query for this category");
        return false;
    }
    QList<QStringList> rows;
    if (!query(sparql, &rows, error))
        return false;
    for (const QStringList &row : std::as_const(rows)) {
        if (row.size() < 5)
            continue;
        const QUrl url(row.at(0));
        if (!url.isLocalFile())
            continue;
        ContentItem item;
        item.filePath = url.toLocalFile();
        const QFileInfo info(item.filePath);
        item.fileName = info.fileName();
        item.mimeType = row.at(1);
        item.title = row.at(2).isEmpty() ? info.completeBaseName() : row.at(2);
        item.fileSize = row.at(3).toLongLong();
        item.lastModified = QDateTime::fromString(row.at(4), Qt::ISODate);
        item.category = category;
        items->append(item);
    }
    return true;
}

} // namespace keel::pickers
