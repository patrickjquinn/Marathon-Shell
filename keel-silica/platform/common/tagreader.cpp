// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "tagreader.h"

#include <QFile>
#include <QStringDecoder>
#include <QtEndian>

namespace keel {

namespace {

constexpr qint64 kMaxRead = static_cast<qint64>(256) * 1024;

quint32 be32(const char *p)
{
    return qFromBigEndian<quint32>(p);
}

quint32 le32(const char *p)
{
    return qFromLittleEndian<quint32>(p);
}

quint32 syncsafe(const char *p)
{
    // ID3v2 sizes: four 7-bit bytes, most significant first.
    const auto *u = reinterpret_cast<const unsigned char *>(p);
    quint32 v = 0;
    for (int i = 0; i < 4; ++i)
        v = (v << 7) | static_cast<quint32>(u[i] & 0x7f);
    return v;
}

QString trimmed(QString s)
{
    const qsizetype nul = s.indexOf(QChar(u'\0'));
    if (nul >= 0)
        s.truncate(nul);
    return s.trimmed();
}

// An ID3v2 text frame body: encoding byte, then the text.
QString id3Text(const QByteArray &body)
{
    if (body.isEmpty())
        return {};
    const QByteArray text = body.mid(1);
    switch (body.at(0)) {
    case 0:
        return trimmed(QString::fromLatin1(text));
    case 1: { // UTF-16 with BOM
        QStringDecoder d(QStringConverter::Utf16, QStringConverter::Flag::ConvertInitialBom);
        if (text.startsWith("\xfe\xff"))
            d = QStringDecoder(QStringConverter::Utf16BE);
        else if (text.startsWith("\xff\xfe"))
            d = QStringDecoder(QStringConverter::Utf16LE);
        const bool bom = text.startsWith("\xfe\xff") || text.startsWith("\xff\xfe");
        return trimmed(d.decode(bom ? text.mid(2) : text));
    }
    case 2: {
        QStringDecoder d(QStringConverter::Utf16BE);
        return trimmed(d.decode(text));
    }
    case 3:
        return trimmed(QString::fromUtf8(text));
    default:
        return {};
    }
}

QString id3v2Title(const QByteArray &data)
{
    if (data.size() < 10 || !data.startsWith("ID3"))
        return {};
    const int major = static_cast<unsigned char>(data.at(3));
    const quint32 tagSize = syncsafe(data.constData() + 6);
    const qsizetype end = qMin<qsizetype>(data.size(), 10 + static_cast<qsizetype>(tagSize));
    qsizetype pos = 10;
    const auto flags = static_cast<unsigned char>(data.at(5));
    if ((flags & 0x40) && major >= 3 && pos + 4 <= end) { // extended header
        const quint32 ext = major == 4 ? syncsafe(data.constData() + pos) : be32(data.constData() + pos) + 4;
        pos += ext;
    }
    if (major == 2) { // three-character ids, three-byte sizes
        while (pos + 6 <= end && data.at(pos) != 0) {
            const QByteArray id = data.mid(pos, 3);
            const auto *u = reinterpret_cast<const unsigned char *>(data.constData() + pos + 3);
            const qsizetype size = (static_cast<qsizetype>(u[0]) << 16) | (static_cast<qsizetype>(u[1]) << 8) | static_cast<qsizetype>(u[2]);
            if (pos + 6 + size > end)
                break;
            if (id == "TT2")
                return id3Text(data.mid(pos + 6, size));
            pos += 6 + size;
        }
        return {};
    }
    while (pos + 10 <= end && data.at(pos) != 0) {
        const QByteArray id = data.mid(pos, 4);
        const quint32 size = major == 4 ? syncsafe(data.constData() + pos + 4) : be32(data.constData() + pos + 4);
        if (size > static_cast<quint32>(end - pos - 10))
            break;
        if (id == "TIT2")
            return id3Text(data.mid(pos + 10, static_cast<qsizetype>(size)));
        pos += 10 + static_cast<qsizetype>(size);
    }
    return {};
}

QString id3v1Title(QFile &file)
{
    if (file.size() < 128 || !file.seek(file.size() - 128))
        return {};
    const QByteArray tag = file.read(128);
    if (!tag.startsWith("TAG"))
        return {};
    return trimmed(QString::fromLatin1(tag.mid(3, 30)));
}

// A Vorbis comment block starting at `pos` (vendor length onwards).
QString vorbisCommentTitle(const QByteArray &data, qsizetype pos)
{
    if (pos + 4 > data.size())
        return {};
    pos += 4 + static_cast<qsizetype>(le32(data.constData() + pos));
    if (pos + 4 > data.size())
        return {};
    const quint32 count = le32(data.constData() + pos);
    pos += 4;
    for (quint32 i = 0; i < count && pos + 4 <= data.size(); ++i) {
        const auto len = static_cast<qsizetype>(le32(data.constData() + pos));
        pos += 4;
        if (len < 0 || pos + len > data.size())
            break;
        const QByteArray entry = data.mid(pos, len);
        pos += len;
        const qsizetype eq = entry.indexOf('=');
        if (eq > 0 && entry.left(eq).compare("TITLE", Qt::CaseInsensitive) == 0)
            return trimmed(QString::fromUtf8(entry.mid(eq + 1)));
    }
    return {};
}

QString oggTitle(const QByteArray &data)
{
    if (!data.startsWith("OggS"))
        return {};
    // The comment packet follows the identification packet, normally in the
    // second page; this reads it when it fits there (no packet reassembly
    // across pages beyond what lies contiguously in the buffer).
    qsizetype at = data.indexOf("\x03vorbis");
    if (at >= 0)
        return vorbisCommentTitle(data, at + 7);
    at = data.indexOf("OpusTags");
    if (at >= 0)
        return vorbisCommentTitle(data, at + 8);
    return {};
}

QString flacTitle(const QByteArray &data)
{
    if (!data.startsWith("fLaC"))
        return {};
    qsizetype pos = 4;
    while (pos + 4 <= data.size()) {
        const auto header = static_cast<unsigned char>(data.at(pos));
        const auto *u = reinterpret_cast<const unsigned char *>(data.constData() + pos + 1);
        const qsizetype len = (static_cast<qsizetype>(u[0]) << 16) | (static_cast<qsizetype>(u[1]) << 8) | static_cast<qsizetype>(u[2]);
        if ((header & 0x7f) == 4) // VORBIS_COMMENT
            return vorbisCommentTitle(data.left(pos + 4 + len), pos + 4);
        if (header & 0x80) // last metadata block
            break;
        pos += 4 + len;
    }
    return {};
}

} // namespace

QString readTitleTag(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QByteArray head = file.read(kMaxRead);
    QString title = id3v2Title(head);
    if (title.isEmpty())
        title = oggTitle(head);
    if (title.isEmpty())
        title = flacTitle(head);
    if (title.isEmpty() && path.endsWith(QLatin1String(".mp3"), Qt::CaseInsensitive))
        title = id3v1Title(file);
    return title;
}

} // namespace keel
