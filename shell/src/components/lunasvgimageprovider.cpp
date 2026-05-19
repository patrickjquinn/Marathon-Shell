#include "lunasvgimageprovider.h"
#include <lunasvg.h>
#include <QFile>
#include <QDebug>
#include <QByteArray>
#include <QStandardPaths>

namespace {

    // App-icon SVGs use `<text font-family="Sora">` to render display marks
    // (e.g. the App Store "M" wordmark and the Calendar "FRI"/"5" tiles).
    // lunasvg 3.x supports `<text>` but only renders glyphs for fonts it
    // has been told about explicitly — its font cache starts empty. Without
    // these registrations the offending icons render as their background
    // rectangle only, which is exactly what shipped: blank squircles.
    //
    // We register Sora once at provider construction. Bold/italic variants
    // of Sora are not in the vendored tree (the variable font ships the
    // wght axis only, no italic), so we point all four face slots at the
    // same TTF and let lunasvg do faux-bold/italic synthesis. For the
    // "M" wordmark this looks correct (italic skew on an Extra-Black weight
    // in lunasvg ≈ the design intent); for the Calendar "FRI"/"5" only the
    // upright Regular slot ever gets matched, so it's a clean hit.
    void registerAppIconFonts() {
        static bool registered = false;
        if (registered) {
            return;
        }
        registered = true;

        QStringList candidates;
        candidates << QStringLiteral(":/qt/qml/MarathonUI/Theme/fonts/Sora.ttf")
                   << QStringLiteral("/usr/share/marathon/fonts/Sora.ttf")
                   << QStandardPaths::locate(QStandardPaths::AppDataLocation,
                                             QStringLiteral("fonts/Sora.ttf"));

        QString resolved;
        for (const auto &c : candidates) {
            if (!c.isEmpty() && QFile::exists(c)) {
                resolved = c;
                break;
            }
        }
        if (resolved.isEmpty()) {
            qWarning() << "[LunaSvgImageProvider] Sora.ttf not found; app-icon"
                          " text marks will not render. Looked in:"
                       << candidates;
            return;
        }

        // qrc paths need to be loaded via QFile + addFontFaceFromData since
        // lunasvg's file-path overload only takes a real filesystem path.
        if (resolved.startsWith(QLatin1Char(':'))) {
            QFile f(resolved);
            if (!f.open(QIODevice::ReadOnly)) {
                qWarning() << "[LunaSvgImageProvider] Failed to open qrc font:" << resolved;
                return;
            }
            const QByteArray data = f.readAll();
            // The buffer must outlive lunasvg's font cache (lifetime of process).
            // Allocate on the heap; the destroy callback is null because we never
            // need to free this — fonts are needed until exit.
            char *buf = new char[data.size()];
            memcpy(buf, data.constData(), data.size());
            for (auto bold : {false, true}) {
                for (auto italic : {false, true}) {
                    lunasvg_add_font_face_from_data("Sora", bold, italic, buf,
                                                    static_cast<size_t>(data.size()), nullptr,
                                                    nullptr);
                }
            }
            // Empty family registers Sora as the fallback font so even SVGs
            // missing a font-family attribute pick it up.
            lunasvg_add_font_face_from_data("", false, false, buf, static_cast<size_t>(data.size()),
                                            nullptr, nullptr);
        } else {
            for (auto bold : {false, true}) {
                for (auto italic : {false, true}) {
                    lunasvg_add_font_face_from_file("Sora", bold, italic,
                                                    resolved.toUtf8().constData());
                }
            }
            lunasvg_add_font_face_from_file("", false, false, resolved.toUtf8().constData());
        }

        qInfo() << "[LunaSvgImageProvider] Registered Sora from" << resolved;
    }

} // namespace

LunaSvgImageProvider::LunaSvgImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image) {
    registerAppIconFonts();
}

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
