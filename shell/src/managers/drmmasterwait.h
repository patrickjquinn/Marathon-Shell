#pragma once

#include <QString>
#include <QStringList>

// The "device" a QT_QPA_EGLFS_KMS_CONFIG file names, or empty.
QString kmsConfigDevice(const QString &configPath);

// The cards eglfs_kms may open: the KMS config's device, else every
// /dev/dri/card* with connectors.
QStringList eglfsKmsCards();

// The kernel makes only the first opener of a card DRM master and never
// promotes a later fd. Waits until no other process holds master on any of
// cards, up to timeoutMs. Returns the ms waited, or -1 on timeout.
int waitForDrmMaster(const QStringList &cards, int timeoutMs);
