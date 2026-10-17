#pragma once

#include <QAudioDevice>
#include <QByteArray>
#include <QList>
#include <QMediaDevices>

// The shell's sounds play on WirePlumber's media role loopbacks
// (61-marathon-media-roles.conf), each with its own level, so an alarm or a
// ringtone is not scaled by the media volume.
namespace MediaRole {
    inline QByteArray sinkName(const char *role) {
        return QByteArrayLiteral("input.loopback.sink.role.") + role;
    }

    // The role's loopback, or the default output where there is none.
    inline QAudioDevice output(const char *role) {
        const QByteArray          name    = sinkName(role);
        const QList<QAudioDevice> outputs = QMediaDevices::audioOutputs();
        for (const QAudioDevice &device : outputs) {
            if (device.id() == name)
                return device;
        }
        return QMediaDevices::defaultAudioOutput();
    }
}
