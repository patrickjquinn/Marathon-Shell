#include "lunasvgimageprovider.h"
#include <lunasvg.h>
#include <QFile>
#include <QDebug>
#include <QByteArray>

LunaSvgImageProvider::LunaSvgImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image) {}

QImage LunaSvgImageProvider::requestImage(const QString &id, QSize *size,
                                          const QSize &requestedSize) {

    QString path = id;
    if (path.startsWith("qrc:/")) {

        path = path.mid(3);
    }

    QString fsPath = path;
    if (!fsPath.startsWith('/') && !fsPath.isEmpty()) {

        fsPath = "/" + fsPath;
    }

    std::unique_ptr<lunasvg::Document> document;

    if (!fsPath.isEmpty() && QFile::exists(fsPath)) {
        document = lunasvg::Document::loadFromFile(fsPath.toStdString());
    } else {

        QString resPath;
        if (path.startsWith(":/")) {
            resPath = path;
        } else if (path.startsWith("/")) {
            resPath = ":" + path;
        } else if (!path.isEmpty()) {
            resPath = ":/" + path;
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

    int  width  = requestedSize.width() > 0 ? requestedSize.width() : 128;
    int  height = requestedSize.height() > 0 ? requestedSize.height() : 128;

    auto bitmap = document->renderToBitmap(width, height);
    if (!bitmap.valid()) {
        qWarning() << "[LunaSvgImageProvider] Failed to render SVG:" << id;
        return QImage();
    }

    QImage image(reinterpret_cast<const uchar *>(bitmap.data()), bitmap.width(), bitmap.height(),
                 static_cast<int>(bitmap.stride()), QImage::Format_ARGB32_Premultiplied);

    QImage result = image.copy();

    if (size) {
        *size = result.size();
    }

    qDebug() << "[LunaSvgImageProvider] Rendered:" << id << "at" << result.size();
    return result;
}
