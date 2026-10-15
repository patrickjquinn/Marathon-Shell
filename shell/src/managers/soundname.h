#pragma once

#include <QFileInfo>
#include <QString>
#include <QStringList>
#include <QUrl>

// Shared with the app runner so pickers format names without a D-Bus call per row.
inline QString formatSoundName(const QString &path) {
    QString    p = path;
    const QUrl url(path);
    if (url.isValid() && url.isLocalFile())
        p = url.toLocalFile();

    QString baseName = QFileInfo(p).baseName();
    baseName.remove("alarm_");
    baseName.remove("ring_");
    baseName.replace('_', ' ');
    baseName.replace('-', ' ');

    QStringList words = baseName.split(' ');
    for (auto &word : words) {
        if (!word.isEmpty())
            word[0] = word[0].toUpper();
    }
    return words.join(' ');
}
