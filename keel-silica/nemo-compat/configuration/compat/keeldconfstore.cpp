// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "keeldconfstore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJSValue>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QLoggingCategory>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>
#include <QtGlobal>

#include <limits>
#include <utility>

namespace {

Q_LOGGING_CATEGORY(lcDConf, "shipwright.keel.dconf")

// JSON gives integers as qlonglong and every list as a QVariantList; give
// back what mlite returns (int where it fits, QStringList for string lists).
QVariant fromStored(const QVariant &value)
{
    switch (value.typeId()) {
    case QMetaType::LongLong: {
        const qlonglong v = value.toLongLong();
        if (v >= std::numeric_limits<int>::min() && v <= std::numeric_limits<int>::max())
            return QVariant(static_cast<int>(v));
        return value;
    }
    case QMetaType::QVariantList: {
        const QVariantList list = value.toList();
        bool allStrings = !list.isEmpty();
        QVariantList out;
        out.reserve(list.size());
        for (const QVariant &v : list) {
            allStrings = allStrings && v.typeId() == QMetaType::QString;
            out.append(fromStored(v));
        }
        if (allStrings)
            return QVariant(value.toStringList());
        return QVariant(out);
    }
    case QMetaType::QVariantMap: {
        QVariantMap out;
        const QVariantMap map = value.toMap();
        for (auto it = map.cbegin(); it != map.cend(); ++it)
            out.insert(it.key(), fromStored(it.value()));
        return QVariant(out);
    }
    default:
        return value;
    }
}

} // namespace

KeelDConfStore *KeelDConfStore::instance()
{
    static KeelDConfStore *store = [] {
        QString fileName = qEnvironmentVariable("KEEL_DCONF_FILE");
        if (fileName.isEmpty()) {
            fileName = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                    + QStringLiteral("/keel/dconf.json");
        }
        return new KeelDConfStore(fileName);
    }();
    return store;
}

KeelDConfStore::KeelDConfStore(QString fileName, QObject *parent)
    : QObject(parent)
    , m_fileName(std::move(fileName))
{
    if (load(&m_values) == LoadResult::Unreadable)
        m_fileUnreadable = true;
    m_watcher = new QFileSystemWatcher(this);
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, &KeelDConfStore::reloadFromDisk);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &KeelDConfStore::reloadFromDisk);
    watch();
}

void KeelDConfStore::watch()
{
    const QFileInfo info(m_fileName);
    if (info.dir().exists() && !m_watcher->directories().contains(info.absolutePath()))
        m_watcher->addPath(info.absolutePath());
    if (info.exists() && !m_watcher->files().contains(info.absoluteFilePath()))
        m_watcher->addPath(info.absoluteFilePath());
}

KeelDConfStore::LoadResult KeelDConfStore::load(QVariantMap *values) const
{
    QFile file(m_fileName);
    if (!file.exists()) {
        values->clear();
        return LoadResult::Missing;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        qCWarning(lcDConf) << "cannot read" << m_fileName << ":" << file.errorString();
        return LoadResult::Unreadable;
    }
    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        qCWarning(lcDConf) << "cannot parse" << m_fileName << ":"
                           << (doc.isNull() ? error.errorString() : QStringLiteral("not an object"))
                           << "; it is kept and will be renamed before the next write";
        return LoadResult::Unreadable;
    }
    *values = doc.object().toVariantMap();
    return LoadResult::Loaded;
}

void KeelDConfStore::reloadFromDisk()
{
    const QVariantMap before = m_values;
    QVariantMap loaded;
    const LoadResult result = load(&loaded);
    watch();
    if (result == LoadResult::Unreadable) {
        // Keep what we had; the next write backs the file up and replaces it.
        m_fileUnreadable = true;
        return;
    }
    m_fileUnreadable = false;
    m_values = loaded;

    QSet<QString> keys;
    for (auto it = before.cbegin(); it != before.cend(); ++it)
        keys.insert(it.key());
    for (auto it = m_values.cbegin(); it != m_values.cend(); ++it)
        keys.insert(it.key());
    for (const QString &key : std::as_const(keys)) {
        if (before.value(key) != m_values.value(key))
            emit keyChanged(key);
    }
}

QVariant KeelDConfStore::normalize(const QVariant &input)
{
    QVariant value = input;
    if (value.userType() == qMetaTypeId<QJSValue>())
        value = value.value<QJSValue>().toVariant();

    switch (value.typeId()) {
    case QMetaType::Bool:
    case QMetaType::Int:
    case QMetaType::LongLong:
    case QMetaType::Double:
    case QMetaType::QString:
        return value;
    case QMetaType::UInt:
    case QMetaType::Short:
    case QMetaType::UShort:
    case QMetaType::Char:
    case QMetaType::SChar:
    case QMetaType::UChar:
        return QVariant(value.toLongLong());
    case QMetaType::ULongLong:
        return QVariant(value.toULongLong());
    case QMetaType::Float:
        return QVariant(value.toDouble());
    case QMetaType::QByteArray:
        return QVariant(QString::fromUtf8(value.toByteArray()));
    case QMetaType::QUrl:
        return QVariant(value.toUrl().toString());
    case QMetaType::QStringList:
        return value;
    case QMetaType::QVariantList: {
        QVariantList out;
        const QVariantList list = value.toList();
        for (const QVariant &v : list) {
            const QVariant n = normalize(v);
            if (!n.isValid())
                return QVariant();
            out.append(n);
        }
        return QVariant(out);
    }
    case QMetaType::QVariantMap: {
        QVariantMap out;
        const QVariantMap map = value.toMap();
        for (auto it = map.cbegin(); it != map.cend(); ++it) {
            const QVariant n = normalize(it.value());
            if (!n.isValid())
                return QVariant();
            out.insert(it.key(), n);
        }
        return QVariant(out);
    }
    default:
        return QVariant();
    }
}

QVariant KeelDConfStore::read(const QString &key, int typeHint) const
{
    const auto it = m_values.constFind(key);
    if (it == m_values.cend())
        return QVariant();
    QVariant value = fromStored(it.value());
    if (typeHint != QMetaType::UnknownType && typeHint != QMetaType::QVariant
            && value.userType() != typeHint) {
        QVariant converted = value;
        if (converted.convert(QMetaType(typeHint)))
            return converted;
    }
    return value;
}

bool KeelDConfStore::write(const QString &key, const QVariant &value)
{
    if (key.isEmpty() || !key.startsWith(QLatin1Char('/')) || key.endsWith(QLatin1Char('/')))
        return false;

    if (!value.isValid()) {
        if (!m_values.contains(key))
            return true;
        m_values.remove(key);
    } else {
        const QVariant n = normalize(value);
        if (!n.isValid())
            return false;
        if (m_values.contains(key) && fromStored(m_values.value(key)) == fromStored(n))
            return true;
        m_values.insert(key, n);
    }
    // The value stays in memory even if the file cannot be written, so that
    // readers in this process see it and a later sync can save it.
    const bool saved = sync();
    emit keyChanged(key);
    return saved;
}

bool KeelDConfStore::clear(const QString &dir)
{
    if (dir.isEmpty())
        return true;
    QStringList removed;
    for (auto it = m_values.begin(); it != m_values.end();) {
        if (it.key().startsWith(dir)) {
            removed.append(it.key());
            it = m_values.erase(it);
        } else {
            ++it;
        }
    }
    if (removed.isEmpty())
        return true;
    const bool saved = sync();
    for (const QString &key : std::as_const(removed))
        emit keyChanged(key);
    return saved;
}

QStringList KeelDConfStore::listDirs(const QString &dir) const
{
    QString prefix = dir;
    if (!prefix.endsWith(QLatin1Char('/')))
        prefix.append(QLatin1Char('/'));
    QStringList dirs;
    for (auto it = m_values.cbegin(); it != m_values.cend(); ++it) {
        if (!it.key().startsWith(prefix))
            continue;
        const int slash = it.key().indexOf(QLatin1Char('/'), prefix.size());
        if (slash < 0)
            continue;
        const QString sub = it.key().left(slash);
        if (!dirs.contains(sub))
            dirs.append(sub);
    }
    return dirs;
}

bool KeelDConfStore::backUpUnreadableFile()
{
    QString backup = m_fileName + QStringLiteral(".corrupt");
    for (int n = 1; QFileInfo::exists(backup); ++n)
        backup = m_fileName + QStringLiteral(".corrupt.%1").arg(n);
    if (!QFile::rename(m_fileName, backup)) {
        qCWarning(lcDConf) << "cannot move the unreadable" << m_fileName << "to" << backup
                           << "; not overwriting it";
        return false;
    }
    qCWarning(lcDConf) << "moved the unreadable" << m_fileName << "to" << backup;
    m_corruptBackup = backup;
    m_fileUnreadable = false;
    return true;
}

bool KeelDConfStore::sync()
{
    const QFileInfo info(m_fileName);
    if (!QDir().mkpath(info.absolutePath())) {
        qCWarning(lcDConf) << "cannot create" << info.absolutePath();
        return false;
    }
    if (m_fileUnreadable && QFileInfo::exists(m_fileName) && !backUpUnreadableFile())
        return false;
    QSaveFile file(m_fileName);
    if (!file.open(QIODevice::WriteOnly)) {
        qCWarning(lcDConf) << "cannot write" << m_fileName << ":" << file.errorString();
        return false;
    }
    const QByteArray json = QJsonDocument(QJsonObject::fromVariantMap(m_values))
            .toJson(QJsonDocument::Indented);
    const bool ok = file.write(json) == json.size() && file.commit();
    if (!ok)
        qCWarning(lcDConf) << "cannot write" << m_fileName << ":" << file.errorString();
    watch();
    return ok;
}
