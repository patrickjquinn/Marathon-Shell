#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QUrl>
#include <QVariant>

// Finds album art for a track: embedded art saved to the cache, or a cover
// image next to the file.
class Artwork : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

  public:
    explicit Artwork(QObject *parent = nullptr);

    // `image` is a QImage from MediaPlayer.metaData; returns "" when it is null.
    Q_INVOKABLE QUrl cache(const QVariant &image, const QUrl &track) const;
    Q_INVOKABLE QUrl folderArt(const QUrl &track) const;

  private:
    QString m_dir;
};
