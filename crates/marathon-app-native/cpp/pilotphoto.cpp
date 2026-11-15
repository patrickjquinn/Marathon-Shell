#include "marathon-app-native/cpp/pilotphoto.h"

#include <QtCore/QDebug>
#include <QtGui/QImage>
#include <QtGui/QImageReader>
#include <QtGui/QImageWriter>

namespace marathon::pilot {

    bool preparePhoto(const QString &src, const QString &dst, int maxSide) {
        QImageReader reader(src);
        reader.setAutoTransform(true);
        QImage image = reader.read();
        if (image.isNull()) {
            qWarning() << "[pilot] photo:" << reader.errorString();
            return false;
        }
        if (image.width() > maxSide || image.height() > maxSide)
            image = image.scaled(maxSide, maxSide, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        QImageWriter writer(dst, "jpeg");
        writer.setQuality(85);
        if (!writer.write(image.convertToFormat(QImage::Format_RGB888))) {
            qWarning() << "[pilot] photo:" << writer.errorString();
            return false;
        }
        return true;
    }

} // namespace marathon::pilot
