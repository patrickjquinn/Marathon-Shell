// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel's fallback backing store for MDConfItem / MDConfGroup on hosts
// without mlite-qt6 (and so without dconf). Device builds link Chum's
// mlite-qt6, which reads and writes the real dconf database; this store is
// only used where that library is missing (see PROVENANCE.md).
//
// Keys are dconf-style absolute paths ("/apps/foo/bar"). Values are kept in
// one JSON file, by default $XDG_CONFIG_HOME/keel/dconf.json, overridable
// with KEEL_DCONF_FILE. Changes made by other processes are picked up through
// a file watch. Supported values follow dconf: bool, numbers, strings, lists
// and maps of those. JSON does not keep the int/double distinction of a whole
// number; a type hint on read restores it.
//
// The file is never lost silently. If it cannot be parsed, the store logs it,
// keeps what it had (nothing, at start-up) and, before its next write, renames
// the unreadable file to "<file>.corrupt" (or "<file>.corrupt.<n>" when that
// exists) so that a person can recover it. A write whose sync fails returns
// false and keeps the new value in memory; the next successful sync saves it.
#ifndef KEELDCONFSTORE_H
#define KEELDCONFSTORE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVariantMap>

class QFileSystemWatcher;

class KeelDConfStore : public QObject
{
    Q_OBJECT
public:
    static KeelDConfStore *instance();
    // A store over `fileName`. Apps use instance(); tests create their own.
    explicit KeelDConfStore(QString fileName, QObject *parent = nullptr);

    QString fileName() const { return m_fileName; }

    // An invalid QVariant means the key is unset.
    QVariant read(const QString &key, int typeHint = QMetaType::UnknownType) const;
    // Writing an invalid QVariant unsets the key. Returns false for values
    // dconf could not store (the value is then ignored, as in mlite), and
    // when the file could not be written (the value is then kept in memory).
    bool write(const QString &key, const QVariant &value);
    // Unsets every key below the directory `dir` (which ends with '/').
    // Returns false when the file could not be written.
    bool clear(const QString &dir);
    // Absolute paths of the directories directly below `dir`.
    QStringList listDirs(const QString &dir) const;
    // Writes the file. Returns false, and logs why, when it could not.
    bool sync();
    // Where the last unreadable file was moved to; empty if none was.
    QString corruptBackup() const { return m_corruptBackup; }

    // Converts a value to what the store keeps; invalid if unsupported.
    static QVariant normalize(const QVariant &input);

signals:
    // Emitted once per key whose value changed, here or in another process.
    void keyChanged(const QString &key);

private:
    enum class LoadResult { Loaded, Missing, Unreadable };
    LoadResult load(QVariantMap *values) const;
    void reloadFromDisk();
    void watch();
    bool backUpUnreadableFile();

    QString m_fileName;
    QVariantMap m_values;
    QFileSystemWatcher *m_watcher = nullptr;
    // The file on disk could not be parsed and has not been backed up yet.
    bool m_fileUnreadable = false;
    QString m_corruptBackup;
};

#endif // KEELDCONFSTORE_H
