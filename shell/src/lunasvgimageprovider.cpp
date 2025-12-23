#include "lunasvgimageprovider.h"
#include <lunasvg.h>
#include <QFile>
#include <QDebug>
#include <QByteArray>

LunaSvgImageProvider::LunaSvgImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image) {}

QImage LunaSvgImageProvider::requestImage(const QString &id, QSize *size,
                                          const QSize &requestedSize) {
    // The id is the file path part of the image:// URL.
    //
    // We support:
    // - absolute filesystem paths: /home/.../icon.svg
    // - Qt resource paths (qrc:/... or :/...)
    // - "images/..." (common when callers strip the leading '/' from qrc paths)
    QString path = id;
    if (path.startsWith("qrc:/")) {
        // Map qrc:/foo -> /foo (Qt resource prefix ":" will be applied below)
        path = path.mid(3);
    }

    // Heuristic: if it looks like a filesystem absolute path, try that first.
    QString fsPath = path;
    if (!fsPath.startsWith('/') && !fsPath.isEmpty()) {
        // Prepend '/' (some QML URLs drop it).
        fsPath = "/" + fsPath;
    }

    std::unique_ptr<lunasvg::Document> document;

    if (!fsPath.isEmpty() && QFile::exists(fsPath)) {
        document = lunasvg::Document::loadFromFile(fsPath.toStdString());
    } else {
        // Try Qt resources
        QString resPath;
        if (path.startsWith(":/")) {
            resPath = path;
        } else if (path.startsWith("/")) {
            resPath = ":" + path; // /images/x.svg -> :/images/x.svg
        } else if (!path.isEmpty()) {
            resPath = ":/" + path; // images/x.svg -> :/images/x.svg
        }

        if (resPath.isEmpty() || !QFile::exists(resPath)) {
            qWarning() << "[LunaSvgImageProvider] File not found (fs or qrc):" << id;
            return QImage();
        }

        QFile f(resPath);
        if (!f.open(QIODevice::ReadOnly)) {
            qWarning() << "[LunaSvgImageProvider] Failed to open resource:" << resPath;
            return QImage();
        }
        const QByteArray data = f.readAll();
        if (data.isEmpty()) {
            qWarning() << "[LunaSvgImageProvider] Empty resource:" << resPath;
            return QImage();
        }
        document = lunasvg::Document::loadFromData(
            std::string(data.constData(), static_cast<size_t>(data.size())));
    }

    if (!document) {
        qWarning() << "[LunaSvgImageProvider] Failed to load SVG:" << id;
        return QImage();
    }

    // Determine output size
    int width  = requestedSize.width() > 0 ? requestedSize.width() : 128;
    int height = requestedSize.height() > 0 ? requestedSize.height() : 128;

    // Render SVG to bitmap
    auto bitmap = document->renderToBitmap(width, height);
    if (!bitmap.valid()) {
        qWarning() << "[LunaSvgImageProvider] Failed to render SVG:" << id;
        return QImage();
    }

    // LunaSVG renders to BGRA format with premultiplied alpha
    // On little-endian systems (x86/ARM), BGRA = B,G,R,A bytes in memory
    // Qt's Format_ARGB32_Premultiplied is stored as BGRA on little-endian
    QImage image(reinterpret_cast<const uchar *>(bitmap.data()), bitmap.width(), bitmap.height(),
                 static_cast<int>(bitmap.stride()), QImage::Format_ARGB32_Premultiplied);

    // Make a deep copy since bitmap data will be freed when function returns
    QImage result = image.copy();

    if (size) {
        *size = result.size();
    }

    qDebug() << "[LunaSvgImageProvider] Rendered:" << id << "at" << result.size();
    return result;
}
