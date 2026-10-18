#ifndef DATAENCRYPTION_H
#define DATAENCRYPTION_H

#include <QString>

// The encrypted data partition (docs/ENCRYPTION.md), as an unprivileged
// process can tell. With the home directory on dm-crypt LUKS: "pin" when
// marathon-data-key last made the quick PIN its startup passphrase, "open"
// otherwise (it unlocks at startup without a PIN). Without: "off" when the
// image has a data partition that erasing would encrypt, "none" when not.
QString dataEncryptionState(const QString &home, const QString &mountInfo = "/proc/self/mountinfo",
                            const QString &sysDevBlock   = "/sys/dev/block",
                            const QString &stateFile     = "/var/lib/marathon-data-key/state",
                            const QString &dataPartition = "/dev/disk/by-partlabel/marathon_data");

#endif
