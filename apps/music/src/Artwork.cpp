#include "Artwork.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QStandardPaths>

namespace {
    constexpr int kMaxSize = 720;
}

Artwork::Artwork(QObject *parent)
    : QObject(parent)
    , m_dir(QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/art") {}

QUrl Artwork::cache(const QVariant &image, const QUrl &track) const {
    QImage art = image.value<QImage>();
    if (art.isNull())
        return {};
    const QString name =
        QCryptographicHash::hash(track.toString().toUtf8(), QCryptographicHash::Md5).toHex();
    const QString path = m_dir + "/" + name + ".jpg";
    if (!QFileInfo::exists(path)) {
        QDir().mkpath(m_dir);
        if (art.width() > kMaxSize || art.height() > kMaxSize)
            art = art.scaled(kMaxSize, kMaxSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        if (!art.save(path, "JPG", 90))
            return {};
    }
    return QUrl::fromLocalFile(path);
}

QUrl Artwork::folderArt(const QUrl &track) const {
    const QDir dir = QFileInfo(track.toLocalFile()).dir();
    for (const char *name : {"cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg",
                             "front.png", "Cover.jpg", "Folder.jpg", "AlbumArt.jpg"}) {
        const QString path = dir.filePath(QString::fromLatin1(name));
        if (QFileInfo::exists(path))
            return QUrl::fromLocalFile(path);
    }
    return {};
}
