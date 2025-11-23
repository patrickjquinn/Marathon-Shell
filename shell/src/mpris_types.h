#ifndef MPRIS_TYPES_H
#define MPRIS_TYPES_H

#include <QMap>
#include <QString>
#include <QVariant>
#include <QDBusMetaType>

// Define the type for MPRIS metadata (a{sv})
typedef QMap<QString, QVariant> MprisMetadata;

Q_DECLARE_METATYPE(MprisMetadata)

inline void registerMprisTypes() {
    qDBusRegisterMetaType<MprisMetadata>();
    qDBusRegisterMetaType<QMap<QString, QVariant>>();
    qDBusRegisterMetaType<QStringList>();
    qDBusRegisterMetaType<QList<QVariant>>();
}

#endif // MPRIS_TYPES_H
