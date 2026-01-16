#ifndef LUNASVGIMAGEPROVIDER_H
#define LUNASVGIMAGEPROVIDER_H

#include <QQuickImageProvider>
#include <QImage>
#include <QString>

class LunaSvgImageProvider : public QQuickImageProvider {
  public:
    LunaSvgImageProvider();

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};

#endif
