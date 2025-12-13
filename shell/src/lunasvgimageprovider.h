#ifndef LUNASVGIMAGEPROVIDER_H
#define LUNASVGIMAGEPROVIDER_H

#include <QQuickImageProvider>
#include <QImage>
#include <QString>

/**
 * @brief QML Image Provider that uses LunaSVG for rendering SVG files.
 * 
 * Qt's built-in SVG renderer doesn't support clipPath elements, which causes
 * GNOME icons to render with black backgrounds. LunaSVG provides full SVG
 * support including clipPath, masks, and filters.
 * 
 * Usage in QML:
 *   Image { source: "image://lunasvg/" + iconPath }
 */
class LunaSvgImageProvider : public QQuickImageProvider {
  public:
    LunaSvgImageProvider();

    /**
     * @brief Render an SVG file to a QImage at the requested size.
     * @param id The file path of the SVG (without "image://lunasvg/" prefix)
     * @param size Requested output size
     * @param requestedSize The size requested by QML (may be invalid)
     * @return Rendered QImage, or empty QImage on failure
     */
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};

#endif // LUNASVGIMAGEPROVIDER_H
