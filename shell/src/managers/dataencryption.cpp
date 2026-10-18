#include "dataencryption.h"

#include <QFile>
#include <QStringList>

namespace {

    QByteArray readFile(const QString &path) {
        QFile f(path);
        return f.open(QIODevice::ReadOnly) ? f.readAll().trimmed() : QByteArray();
    }

    // mountinfo escapes space, tab, newline and backslash as \ooo.
    QString unescapeMountPoint(const QString &field) {
        QString out;
        for (qsizetype i = 0; i < field.size(); ++i) {
            if (field[i] == u'\\' && i + 3 < field.size()) {
                bool       ok   = false;
                const uint code = field.mid(i + 1, 3).toUInt(&ok, 8);
                if (ok) {
                    out += QChar(code);
                    i += 3;
                    continue;
                }
            }
            out += field[i];
        }
        return out;
    }

    // The major:minor of the mount that holds path.
    QString deviceOf(const QString &path, const QString &mountInfo) {
        QString          device;
        qsizetype        best = -1;
        const QByteArray        info  = readFile(mountInfo);
        const QList<QByteArray> lines = info.split('\n');
        for (const QByteArray &line : lines) {
            const QStringList fields = QString::fromUtf8(line).split(u' ');
            if (fields.size() < 5)
                continue;
            const QString mountPoint = unescapeMountPoint(fields[4]);
            const bool    holds =
                mountPoint == u"/" || path == mountPoint || path.startsWith(mountPoint + u'/');
            // Later lines are mounted on top of earlier ones.
            if (holds && mountPoint.size() >= best) {
                best   = mountPoint.size();
                device = fields[2];
            }
        }
        return device;
    }

} // namespace

QString dataEncryptionState(const QString &home, const QString &mountInfo,
                            const QString &sysDevBlock, const QString &stateFile,
                            const QString &dataPartition) {
    const QString device = deviceOf(home, mountInfo);
    if (device.isEmpty() ||
        !readFile(sysDevBlock + u'/' + device + QStringLiteral("/dm/uuid"))
             .startsWith("CRYPT-LUKS"))
        return QFile::exists(dataPartition) ? QStringLiteral("off") : QStringLiteral("none");
    return readFile(stateFile) == "pin" ? QStringLiteral("pin") : QStringLiteral("open");
}
