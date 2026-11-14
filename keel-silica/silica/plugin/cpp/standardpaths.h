// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// StandardPaths singleton (Silica public API: cache, data, documents,
// download, genericData, home, music, pictures, temporary, videos).
// Clean-room over QStandardPaths.
#ifndef KEEL_STANDARDPATHS_H
#define KEEL_STANDARDPATHS_H

#include <QObject>
#include <QStandardPaths>
#include <QtQml/qqmlregistration.h>

class KeelStandardPaths : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(StandardPaths)
    QML_SINGLETON
    Q_PROPERTY(QString cache READ cache CONSTANT)
    Q_PROPERTY(QString data READ data CONSTANT)
    Q_PROPERTY(QString documents READ documents CONSTANT)
    Q_PROPERTY(QString download READ download CONSTANT)
    Q_PROPERTY(QString genericData READ genericData CONSTANT)
    Q_PROPERTY(QString home READ home CONSTANT)
    Q_PROPERTY(QString music READ music CONSTANT)
    Q_PROPERTY(QString pictures READ pictures CONSTANT)
    Q_PROPERTY(QString temporary READ temporary CONSTANT)
    Q_PROPERTY(QString videos READ videos CONSTANT)

public:
    using QObject::QObject;

    static QString location(QStandardPaths::StandardLocation l) { return QStandardPaths::writableLocation(l); }
    QString cache() const { return location(QStandardPaths::CacheLocation); }
    QString data() const { return location(QStandardPaths::AppDataLocation); }
    QString documents() const { return location(QStandardPaths::DocumentsLocation); }
    QString download() const { return location(QStandardPaths::DownloadLocation); }
    QString genericData() const { return location(QStandardPaths::GenericDataLocation); }
    QString home() const { return location(QStandardPaths::HomeLocation); }
    QString music() const { return location(QStandardPaths::MusicLocation); }
    QString pictures() const { return location(QStandardPaths::PicturesLocation); }
    QString temporary() const { return location(QStandardPaths::TempLocation); }
    QString videos() const { return location(QStandardPaths::MoviesLocation); }
};

#endif
