#include "lunasvgimageprovider.h"
#include <lunasvg.h>
#include <QFile>
#include <QDebug>

LunaSvgImageProvider::LunaSvgImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image) {}

QImage LunaSvgImageProvider::requestImage(const QString &id, QSize *size,
                                          const QSize &requestedSize) {
    // The id is the file path
    // QML image URLs like "image://lunasvg/path" pass "path" as id
    // Absolute paths starting with / become paths without leading /
    // So we need to prepend / if missing (for absolute paths)
    QString filePath = id;
    if (!filePath.startsWith('/') && !filePath.isEmpty()) {
        // Prepend / for absolute paths that lost it in URL parsing
        filePath = "/" + filePath;
    }

    if (!filePath.startsWith('/')) {
        qWarning() << "[LunaSvgImageProvider] Expected absolute path, got:" << id;
        return QImage();
    }

    // Check if file exists
    if (!QFile::exists(filePath)) {
        qWarning() << "[LunaSvgImageProvider] File not found:" << filePath;
        return QImage();
    }

    // Load SVG document with LunaSVG
    auto document = lunasvg::Document::loadFromFile(filePath.toStdString());
    if (!document) {
        qWarning() << "[LunaSvgImageProvider] Failed to load SVG:" << filePath;
        return QImage();
    }

    // Determine output size
    int width  = requestedSize.width() > 0 ? requestedSize.width() : 128;
    int height = requestedSize.height() > 0 ? requestedSize.height() : 128;

    // Render SVG to bitmap
    auto bitmap = document->renderToBitmap(width, height);
    if (!bitmap.valid()) {
        qWarning() << "[LunaSvgImageProvider] Failed to render SVG:" << filePath;
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

    qDebug() << "[LunaSvgImageProvider] Rendered:" << filePath << "at" << result.size();
    return result;
}
