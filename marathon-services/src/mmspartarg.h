#pragma once

#include <QDBusArgument>
#include <QDBusUnixFileDescriptor>
#include <QList>
#include <QMetaType>
#include <QString>

// A part of an MMS as an app hands it to Sms1.SendMms: (content type, file
// name, descriptor), a(ssh). The descriptor is the app's open file, so no
// path crosses the bus.
struct MmsPartArg {
    QString                 contentType;
    QString                 name;
    QDBusUnixFileDescriptor fd;
};
Q_DECLARE_METATYPE(MmsPartArg)

inline QDBusArgument &operator<<(QDBusArgument &arg, const MmsPartArg &part) {
    arg.beginStructure();
    arg << part.contentType << part.name << part.fd;
    arg.endStructure();
    return arg;
}

inline const QDBusArgument &operator>>(const QDBusArgument &arg, MmsPartArg &part) {
    arg.beginStructure();
    arg >> part.contentType >> part.name >> part.fd;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter) QDBusArgument >> signature
}
