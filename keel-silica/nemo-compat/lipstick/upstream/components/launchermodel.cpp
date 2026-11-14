// SPDX-FileCopyrightText: 2012 Timur Kristóf
// SPDX-License-Identifier: LGPL-2.1-only


// This file is part of lipstick, a QML desktop library
//
// This library is free software; you can redistribute it and/or
// modify it under the terms of the GNU Lesser General Public
// License version 2.1 as published by the Free Software Foundation
// and appearing in the file LICENSE.LGPL included in the packaging
// of this file.
//
// This code is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// Copyright (c) 2012, Timur Kristóf <venemo@fedoraproject.org>

#include <QDir>
#include <QFileSystemWatcher>
#include <QDBusConnection>
#include <QDebug>
#include <QFile>
#include <QSettings>
#include <QStandardPaths>

#include "launcheritem.h"
#include "launchermodel.h"

#define LAUNCHER_APPS_PATH "/usr/share/applications/"

// Make sure to also update this in the .spec file, so it gets
// created whenever lipstick is installed, otherwise monitoring
// will fail and newly-installed icons will not be detected
#define LAUNCHER_ICONS_PATH "/usr/share/icons/hicolor/86x86/apps/"

// Time in millseconds to wait before removing temporary launchers
#define LAUNCHER_UPDATING_REMOVAL_HOLDBACK_MS 3000

static inline bool isDesktopFile(const QStringList &applicationPaths, const QString &filename)
{
    if (!filename.endsWith(QStringLiteral(".desktop"))) {
        return false;
    } else foreach (const QString &path, applicationPaths) {
        if (filename.startsWith(path)) {
            return true;
        }
    }
    return false;
}

static inline bool isIconFile(const QString &filename)
{
    // TODO: Possibly support other file types
    return filename.startsWith(QLatin1Char('/')) && filename.endsWith(".png");
}

static inline QString filenameFromIconId(const QString &filename, const QString &path)
{
    return path + filename + QStringLiteral(".png");
}

static inline bool isVisibleDesktopFile(const QString &filename)
{
    LauncherItem item;
    item.setFilePath(filename);

    return item.isValid() && item.shouldDisplay();
}

static QStringList defaultDirectories()
{
    QString userLocalAppsPath = QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
    QDir userLocalLauncherDir(userLocalAppsPath);
    if (!userLocalLauncherDir.exists()) {
        userLocalLauncherDir.mkpath(userLocalAppsPath);
    }

    return QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
}

Q_GLOBAL_STATIC(LauncherDBus, _launcherDBus)

LauncherModel::LauncherModel(QObject *parent)
    : QObjectListModel(parent)
    , m_directories(defaultDirectories())
    , m_iconDirectories(LAUNCHER_ICONS_PATH)
    , m_fileSystemWatcher()
    , m_launcherSettings("nemomobile", "lipstick")
    , m_globalSettings("/usr/share/lipstick/lipstick.conf", QSettings::IniFormat)
    , m_launcherOrderPrefix(QStringLiteral("LauncherOrder/"))
    , m_dbusWatcher(this)
    , m_packageNameToDBusService()
    , m_temporaryLaunchers()
    , m_initialized(false)
{
    initialize();
}

LauncherModel::LauncherModel(InitializationMode, QObject *parent)
    : QObjectListModel(parent)
    , m_directories(defaultDirectories())
    , m_iconDirectories(LAUNCHER_ICONS_PATH)
    , m_fileSystemWatcher()
    , m_launcherSettings("nemomobile", "lipstick")
    , m_globalSettings("/usr/share/lipstick/lipstick.conf", QSettings::IniFormat)
    , m_launcherOrderPrefix(QStringLiteral("LauncherOrder/"))
    , m_dbusWatcher(this)
    , m_packageNameToDBusService()
    , m_temporaryLaunchers()
    , m_initialized(false)
{
}

void LauncherModel::initialize()
{
    if (m_initialized)
        return;
    m_initialized = true;

    _launcherDBus()->registerModel(this);

    QStringList iconDirectories = m_iconDirectories;
    if (!iconDirectories.contains(LAUNCHER_ICONS_PATH))
        iconDirectories << LAUNCHER_ICONS_PATH;

    m_launcherMonitor.setDirectories(m_directories);
    m_launcherMonitor.setIconDirectories(iconDirectories);

    // Set up the monitor for icon and desktop file changes
    connect(&m_launcherMonitor, &LauncherMonitor::filesUpdated,
            this, &LauncherModel::onFilesUpdated);

    // Start monitoring
    m_launcherMonitor.start();

    // Save order of icons when model is changed
    connect(this, &LauncherModel::rowsMoved,
            this, &LauncherModel::savePositions);

    // Watch for changes to the item order settings file
    m_fileSystemWatcher.addPath(m_launcherSettings.fileName());
    connect(&m_fileSystemWatcher, &QFileSystemWatcher::fileChanged,
            this, &LauncherModel::monitoredFileChanged);

    // Used to watch for owner changes during installation progress
    m_dbusWatcher.setConnection(QDBusConnection::sessionBus());
    m_dbusWatcher.setWatchMode(QDBusServiceWatcher::WatchForUnregistration);

    connect(&m_dbusWatcher, &QDBusServiceWatcher::serviceUnregistered,
            this, &LauncherModel::onServiceUnregistered);
}

LauncherModel::~LauncherModel()
{
    _launcherDBus()->deregisterModel(this);
}

void LauncherModel::onFilesUpdated(const QStringList &added,
                                   const QStringList &modified, const QStringList &removed)
{
    QStringList addedFiles = added;
    QStringList removedFiles = removed;
    QStringList modifiedAndNeedUpdating = modified;

    // Keep the existing launcher item when a desktop file is replaced by
    // another file with the same configured identity, so consumers do not
    // mistake the change for an application uninstall.
    QMap<QString, QStringList> replacementFiles;
    if (!m_replacementIdentityKey.isEmpty()) {
        for (const QString &filename : addedFiles) {
            if (!isDesktopFile(m_directories, filename)) {
                continue;
            }

            LauncherItem replacementItem;
            replacementItem.setFilePath(filename);

            if (replacementItem.isValid() && replacementItem.shouldDisplay()
                    && displayCategory(&replacementItem)) {
                const QString identity = replacementItem.readValue(m_replacementIdentityKey);
                if (!identity.isEmpty()) {
                    replacementFiles[identity].append(filename);
                }
            }
        }

        for (int i = removedFiles.count() - 1; i >= 0; --i) {
            const QString oldFilePath = removedFiles.at(i);
            LauncherItem *item = itemInModel(oldFilePath);
            if (!item) {
                continue;
            }

            const QString identity = item->readValue(m_replacementIdentityKey);
            QMap<QString, QStringList>::iterator replacement = replacementFiles.find(identity);
            if (identity.isEmpty() || replacement == replacementFiles.end()) {
                continue;
            }

            const QString newFilePath = replacement.value().takeFirst();
            if (replacement.value().isEmpty()) {
                replacementFiles.erase(replacement);
            }

            LAUNCHER_DEBUG("Replacing launcher item:" << oldFilePath << "with" << newFilePath);
            item->setIconFilename(QString());
            item->setFilePath(newFilePath);
            item->invalidateCaches();

            addedFiles.removeOne(newFilePath);
            removedFiles.removeAt(i);

            updateItemsWithIcon(item->getOriginalIconId(), QString());
            emit launcherReplaced(item, oldFilePath);
        }
    }

    // First, remove all removed launcher items before adding new ones
    for (const QString &filename : removedFiles) {
        if (isDesktopFile(m_directories, filename)) {
            // Desktop file has been removed - remove launcher
            LauncherItem *item = itemInModel(filename);
            if (item != nullptr) {
                LAUNCHER_DEBUG("Removing launcher item:" << filename);
                unsetTemporary(item);
                removeItem(item);
            } else {
                item = takeHiddenItem(filename);
            }
            delete item;
        }
    }

    for (const QString &filename : addedFiles) {
        if (isDesktopFile(m_directories, filename)) {
            // New desktop file appeared - add launcher
            LauncherItem *item = itemInModel(filename);

            // Check if there is a temporary launcher item, and if so, assume that
            // the newly-appeared file (if it is visible) will replace the temporary
            // launcher. In general, this should not happen if the app is properly
            // packaged (desktop file shares basename with packagename), but in some
            // cases, this is better than having the temporary and non-temporary in
            // place at the same time.
            LauncherItem *tempItem = temporaryItemToReplace();
            if (item == nullptr && tempItem != nullptr
                    && isVisibleDesktopFile(filename)) {
                // Replace the single temporary launcher with the newly-added icon
                item = tempItem;

                qWarning() << "Applying heuristics:" << filename
                           << "is the launcher item for" << item->packageName();
                item->setIconFilename("");
                item->setFilePath(filename);
            }

            if (item == nullptr) {
                LAUNCHER_DEBUG("Trying to add launcher item:" << filename);
                item = addItemIfValid(filename);

                if (item != nullptr) {
                    updateItemsWithIcon(item->getOriginalIconId(), QString());
                }
            } else {
                // This case happens if a .desktop file is found as new, but we
                // already have an entry for it, which usually means it was a
                // temporary launcher that we now successfully can replace.
                qWarning() << "Expected file arrives:" << filename;
                unsetTemporary(item);

                // Act as if this filename has been modified, so we can update
                // it below (e.g. turn a temporary item into a permanent one)
                modifiedAndNeedUpdating << filename;
            }
        } else if (isIconFile(filename)) {
            updateItemsWithIcon(QString(), filename);
        }
    }

    for (const QString &filename : modifiedAndNeedUpdating) {
        if (isDesktopFile(m_directories, filename)) {
            // Desktop file has been updated - update launcher
            LauncherItem *item = itemInModel(filename);
            if (item != nullptr) {
                item->invalidateCaches();
                bool isValid = item->isStillValid() && item->shouldDisplay() && displayCategory(item);

                if (!isValid) {
                    // File has changed in such a way (e.g. Hidden=true) that
                    // it now should become invisible again
                    unsetTemporary(item);
                    removeItem(item);
                } else {
                    updateItemsWithIcon(item->getOriginalIconId(), QString());
                }
            } else if ((item = takeHiddenItem(filename))) {
                delete item;
                addItemIfValid(filename);
            } else {
                // No item yet (maybe it had Hidden=true before), try to see if
                // we should show the item now
                addItemIfValid(filename);
            }
        }
    }

    reorderItems();
    savePositions();
}

void LauncherModel::updateItemsWithIcon(const QString &iconId, const QString &iconFilename)
{
    LAUNCHER_DEBUG("updateItemsWithIcon: iconId=" << iconId << "filename=" << iconFilename);

    QStringList iconDirectories = m_launcherMonitor.iconDirectories();

    // Try to determine icon id from filename
    QString id = iconId;
    if (id.isEmpty() && !iconFilename.isEmpty()) {
        QFileInfo fileInfo(iconFilename);
        if (iconDirectories.contains(fileInfo.path() + "/")) {
            id = fileInfo.baseName();
        }
    }

    // Prefer to use scalable icons in icon directories, sorted by the closest icon size
    QString scalableIconFilename;
    if (!id.isEmpty()) {
        for (const QString &iconPath : iconDirectories) {
            QString filename = filenameFromIconId(id, iconPath);
            if (QFile(filename).exists()) {
                scalableIconFilename = filename;
                break;
            }
        }
    }

    if (!scalableIconFilename.isEmpty()) {
        // Use the most suitable scalable icon in the launcher items that share the icon id
        for (LauncherItem *item : *getList<LauncherItem>()) {
            if (id == item->getOriginalIconId()) {
                item->setIconFilename(scalableIconFilename);
                LAUNCHER_DEBUG("Scalable icon" << scalableIconFilename << "was updated for id" << id);
            }
        }
    }
}

void LauncherModel::monitoredFileChanged(const QString &changedPath)
{
    if (changedPath == m_launcherSettings.fileName()) {
        loadPositions();
    } else {
        qWarning() << "Unknown monitored file in LauncherModel:" << changedPath;
    }
}

void LauncherModel::loadPositions()
{
    m_launcherSettings.sync();
    reorderItems();
}

void LauncherModel::reorderItems()
{
    QMap<int, LauncherItem *> itemsWithPositions;
    QMap<QString, LauncherItem *> itemsWithoutPositions;

    QList<LauncherItem *> *currentLauncherList = getList<LauncherItem>();
    foreach (LauncherItem *item, *currentLauncherList) {
        QVariant pos = launcherPos(item->filePath());

        if (pos.isValid()) {
            int gridPos = pos.toInt();
            itemsWithPositions.insert(gridPos, item);
        } else {
            itemsWithoutPositions.insert(item->title(), item);
        }
    }

    QList<LauncherItem *> reordered;
    {
        // Order the positioned items into contiguous order
        QMap<int, LauncherItem *>::const_iterator it = itemsWithPositions.constBegin(),
                end = itemsWithPositions.constEnd();
        for ( ; it != end; ++it) {
            LAUNCHER_DEBUG("Planned move of" << it.value()->title() << "to" << reordered.count());
            reordered.append(it.value());
        }
    }
    {
        // Append the un-positioned items in sorted-by-title order
        QMap<QString, LauncherItem *>::const_iterator it = itemsWithoutPositions.constBegin(),
                end = itemsWithoutPositions.constEnd();
        for ( ; it != end; ++it) {
            LAUNCHER_DEBUG("Planned move of" << it.value()->title() << "to" << reordered.count());
            reordered.append(it.value());
        }
    }

    for (int gridPos = 0; gridPos < reordered.count(); ++gridPos) {
        LauncherItem *item = reordered.at(gridPos);
        LAUNCHER_DEBUG("Moving" << item->filePath() << "to" << gridPos);

        if (gridPos < 0 || gridPos >= itemCount()) {
            LAUNCHER_DEBUG("Invalid planned position for" << item->filePath());
            continue;
        }

        int currentPos = indexOf(item);
        Q_ASSERT(currentPos >= 0);
        if (currentPos == -1)
            continue;

        if (gridPos == currentPos)
            continue;

        move(currentPos, gridPos);
    }
}

QStringList LauncherModel::directories() const
{
    return m_directories;
}

static QStringList suffixDirectories(const QStringList &directories)
{
    QStringList copy = directories;
    for (int i = 0; i < directories.count(); ++i) {
        if (!directories.at(i).endsWith(QLatin1Char('/'))) {
            copy.replace(i, directories.at(i) + QLatin1Char('/'));
        }
    }
    return copy;
}

void LauncherModel::setDirectories(QStringList newDirectories)
{
    newDirectories = suffixDirectories(newDirectories);

    if (m_directories != newDirectories) {
        m_directories = newDirectories;
        emit directoriesChanged();

        if (m_initialized) {
            m_launcherMonitor.setDirectories(m_directories);
        }
    }
}

QStringList LauncherModel::iconDirectories() const
{
    return m_iconDirectories;
}

void LauncherModel::setIconDirectories(QStringList newDirectories)
{
    newDirectories = suffixDirectories(newDirectories);

    if (m_iconDirectories != newDirectories) {
        m_iconDirectories = newDirectories;
        emit iconDirectoriesChanged();

        if (m_initialized) {
            newDirectories = m_iconDirectories;
            if (!newDirectories.contains(LAUNCHER_ICONS_PATH))
                newDirectories << LAUNCHER_ICONS_PATH;
            m_launcherMonitor.setIconDirectories(newDirectories);
        }
    }
}

QStringList LauncherModel::categories() const
{
    return m_categories;
}

void LauncherModel::setCategories(const QStringList &categories)
{
    if (m_categories != categories) {
        m_categories = categories;
        emit categoriesChanged();

        if (m_initialized) {
            // Force a complete rebuild of the model.
            m_launcherMonitor.reset(m_directories);
        }
    }
}

QStringList LauncherModel::blacklistedApplications() const
{
    return m_blacklistedApplications;
}

void LauncherModel::setBlacklistedApplications(const QStringList &blacklistedApplications)
{
    if (m_blacklistedApplications != blacklistedApplications) {
        m_blacklistedApplications = blacklistedApplications;
        emit blacklistedApplicationsChanged();
    }
}

QString LauncherModel::replacementIdentityKey() const
{
    return m_replacementIdentityKey;
}

void LauncherModel::setReplacementIdentityKey(const QString &key)
{
    if (m_replacementIdentityKey != key) {
        m_replacementIdentityKey = key;
        emit replacementIdentityKeyChanged();
    }
}

QString LauncherModel::scope() const
{
    return m_scope;
}

void LauncherModel::setScope(const QString &scope)
{
    if (m_scope != scope) {
        m_scope = scope;
        m_launcherOrderPrefix = !m_scope.isEmpty()
                ? scope + QStringLiteral("/LauncherOrder/")
                : QStringLiteral("LauncherOrder/");
        emit scopeChanged();

        if (m_initialized) {
            loadPositions();
        }
    }
}

static QString desktopFileFromPackageName(const QStringList &directories, const QString &packageName)
{
    // Using the package name as base name for the desktop file is a good
    // heuristic, and usually works fine.
    foreach (const QString &directory, directories) {
        QString desktopFile = directory + packageName + QStringLiteral(".desktop");
        if (QFile::exists(desktopFile)) {
            return desktopFile;
        }
    }

    return QStringLiteral(LAUNCHER_APPS_PATH) + packageName + QStringLiteral(".desktop");
}

void LauncherModel::updatingStarted(const QString &packageName, const QString &label,
                                    const QString &iconPath, QString desktopFile, const QString &serviceName)
{
    LAUNCHER_DEBUG("Update started:" << packageName << label << iconPath << desktopFile);

    // Remember which service notified us about this package, so we can
    // clean up existing updates when the service vanishes from D-Bus.
    m_packageNameToDBusService[packageName] = serviceName;
    m_dbusWatcher.addWatchedService(serviceName);

    if (desktopFile.isEmpty()) {
        desktopFile = desktopFileFromPackageName(m_directories, packageName);
    }

    LauncherItem *item = itemInModel(desktopFile);

    if (!item) {
        item = packageInModel(packageName);
    }

    if (item) {
        if (item->isTemporary()) {
            // Calling updatingStarted on an existing temporary icon should
            // update the internal state of the temporary icon (and if the
            // .desktop file exists, make the icon non-temporary).
            if (!label.isEmpty()) {
                item->setCustomTitle(label);
            }

            if (!iconPath.isEmpty()) {
                item->setIconFilename(iconPath);
            }

            if (!desktopFile.isEmpty() && isDesktopFile(m_directories, desktopFile)) {
                // Only update the .desktop file name if we actually consider
                // it a .desktop file in the paths we monitor for changes (JB#29427)
                item->setFilePath(desktopFile);
                // XXX: Changing the .desktop file path might hide the icon;
                // we don't handle this here, but expect onFilesUpdated() to be
                // called with the correct file names via the filesystem monitor
            }

            if (QFile(desktopFile).exists()) {
                // The file has appeared - remove temporary flag
                unsetTemporary(item);
            }
        } else {
            // if there's first update notification without desktop file info and the guess made here fails,
            // a temporary item will be created.
            // if then after that there's update notification with both desktop file and package name,
            // need to remove the temporary one.
            foreach (LauncherItem *item, m_temporaryLaunchers) {
                if (item->packageName() == packageName) {
                    // Will remove it from _temporaryLaunchers
                    unsetTemporary(item);
                    removeItem(item);
                    break;
                }
            }
        }
    }

    if (!item && isDesktopFile(m_directories, desktopFile)) {
        // Newly-installed package: Create temporary icon with label and icon
        item = new LauncherItem(packageName, label, iconPath, desktopFile, this);
        setTemporary(item);
        addItem(item);
    }

    if (item) {
        item->setUpdatingProgress(-1);
        item->setIsUpdating(true);
        item->setPackageName(packageName);
    }
}

void LauncherModel::updatingProgress(const QString &packageName, int progress, const QString &serviceName)
{
    LAUNCHER_DEBUG("Update progress:" << packageName << progress);

    QString expectedServiceName = m_packageNameToDBusService[packageName];
    if (expectedServiceName != serviceName) {
        qWarning() << "Got update from" << serviceName
                   << "but expected update from" << expectedServiceName;
    }

    LauncherItem *item = packageInModel(packageName);

    if (!item) {
        qWarning() << "Package not found in model:" << packageName;
        return;
    }

    item->setUpdatingProgress(progress);
    item->setIsUpdating(true);
}

void LauncherModel::updatingFinished(const QString &packageName, const QString &serviceName)
{
    LAUNCHER_DEBUG("Update finished:" << packageName);

    QString expectedServiceName = m_packageNameToDBusService[packageName];
    if (expectedServiceName != serviceName) {
        qWarning() << "Got update from" << serviceName
                   << "but expected update from" << expectedServiceName;
    }

    m_packageNameToDBusService.remove(packageName);
    updateWatchedDBusServices();

    LauncherItem *item = packageInModel(packageName);

    if (!item) {
        if (m_directories.contains(LAUNCHER_APPS_PATH)) {
            qWarning() << "Package not found in model:" << packageName;
        }
        return;
    }

    item->setIsUpdating(false);
    item->setUpdatingProgress(-1);
    item->setPackageName("");
    if (item->isTemporary()) {
        // Schedule removal of temporary icons
        QTimer::singleShot(LAUNCHER_UPDATING_REMOVAL_HOLDBACK_MS,
                           this, &LauncherModel::removeTemporaryLaunchers);
    }
}

void LauncherModel::notifyLaunching(const QString &desktopFile)
{
    LauncherItem *item = itemInModel(desktopFile);
    if (item) {
        item->setIsLaunching(true);
        emit notifyLaunching(item);
    } else {
        qWarning("No launcher item found for \"%s\".", qPrintable(desktopFile));
    }
}

void LauncherModel::cancelNotifyLaunching(const QString &desktopFile)
{
    LauncherItem *item = itemInModel(desktopFile);
    if (item) {
        item->setIsLaunching(false);
        emit canceledNotifyLaunching(item);
    } else {
        qWarning("No launcher item found for \"%s\".", qPrintable(desktopFile));
    }
}

void LauncherModel::updateWatchedDBusServices()
{
    QStringList requiredServices = m_packageNameToDBusService.values();

    foreach (const QString &service, m_dbusWatcher.watchedServices()) {
        if (!requiredServices.contains(service)) {
            LAUNCHER_DEBUG("Don't need to watch service anymore:" << service);
            m_dbusWatcher.removeWatchedService(service);
        }
    }
}

void LauncherModel::onServiceUnregistered(const QString &serviceName)
{
    qWarning() << "Service" << serviceName << "vanished";
    m_dbusWatcher.removeWatchedService(serviceName);

    QStringList packagesToRemove;
    QMap<QString, QString>::iterator it;
    for (it = m_packageNameToDBusService.begin(); it != m_packageNameToDBusService.end(); ++it) {
        if (it.value() == serviceName) {
            qWarning() << "Service" << serviceName << "was active for" << it.key();
            packagesToRemove << it.key();
        }
    }

    foreach (const QString &packageName, packagesToRemove) {
        LAUNCHER_DEBUG("Fabricating updatingFinished for" << packageName);
        updatingFinished(packageName, serviceName);
    }
}

void LauncherModel::removeTemporaryLaunchers()
{
    QList<LauncherItem *> iterationCopy = m_temporaryLaunchers;
    foreach (LauncherItem *item, iterationCopy) {
        if (!item->isUpdating()) {
            // Temporary item that is not updating at the moment
            LAUNCHER_DEBUG("Removing temporary launcher");
            // Will remove it from _temporaryLaunchers
            unsetTemporary(item);
            removeItem(item);
        }
    }
}

void LauncherModel::requestLaunch(const QString &packageName)
{
    // Send launch request via D-Bus, so interested parties can act upon it
    _launcherDBus()->requestLaunch(packageName);
}

void LauncherModel::savePositions()
{
    m_fileSystemWatcher.removePath(m_launcherSettings.fileName());

    m_launcherSettings.remove(m_launcherOrderPrefix.left(m_launcherOrderPrefix.count() - 1));
    QList<LauncherItem *> *currentLauncherList = getList<LauncherItem>();

    int pos = 0;
    foreach (LauncherItem *item, *currentLauncherList) {
        m_launcherSettings.setValue(m_launcherOrderPrefix + item->filePath(), pos);
        ++pos;
    }

    m_launcherSettings.sync();
    m_fileSystemWatcher.addPath(m_launcherSettings.fileName());
}

int LauncherModel::findItem(const QString &path, LauncherItem **item)
{
    QList<LauncherItem*> *list = getList<LauncherItem>();
    for (int i = 0; i < list->count(); ++i) {
        LauncherItem *listItem = list->at(i);
        if (listItem->filePath() == path || listItem->filename() == path) {
            if (item)
                *item = listItem;
            return i;
        }
    }

    if (item) {
        *item = nullptr;
    }

    return -1;
}

LauncherItem *LauncherModel::itemInModel(const QString &path)
{
    LauncherItem *result = 0;
    (void)findItem(path, &result);
    return result;
}

LauncherItem *LauncherModel::takeHiddenItem(const QString &path)
{
    for (int i = 0; i < m_hiddenLaunchers.count(); ++i) {
        LauncherItem *item = m_hiddenLaunchers.at(i);

        if (item->filePath() == path || item->filename() == path) {
            m_hiddenLaunchers.removeAt(i);
            return item;
        }
    }
    return nullptr;
}

int LauncherModel::indexInModel(const QString &path)
{
    return findItem(path, 0);
}

QList<LauncherItem *> LauncherModel::itemsForMimeType(const QString &mimeType)
{
    QList<LauncherItem *> items;

    for (QObject *object : *getList()) {
         LauncherItem *item = static_cast<LauncherItem *>(object);
         if (item->canOpenMimeType(mimeType)) {
             items.append(item);
         }
    }
    for (LauncherItem *item : m_hiddenLaunchers) {
        if (item->canOpenMimeType(mimeType)) {
            items.append(item);
        }
    }
    return items;
}

static bool matchDBusName(const QString &name, const QString launcherName)
{
    return name == launcherName || name.startsWith(launcherName + QLatin1Char('.'));
}

LauncherItem *LauncherModel::itemForService(const QString &name)
{
    if (name.isEmpty()) {
        return nullptr;
    }

    for (QObject *object : *getList()) {
         LauncherItem *item = static_cast<LauncherItem *>(object);
         if (matchDBusName(name, item->dBusServiceName())) {
             return item;
         }
    }
    for (LauncherItem *item : m_hiddenLaunchers) {
        if (matchDBusName(name, item->dBusServiceName())) {
            return item;
        }
    }
    return nullptr;
}

LauncherItem *LauncherModel::packageInModel(const QString &packageName)
{
    QList<LauncherItem *> *list = getList<LauncherItem>();

    QList<LauncherItem *>::const_iterator it = list->constEnd();
    while (it != list->constBegin()) {
        --it;

        if ((*it)->packageName() == packageName) {
            return *it;
        }
    }

    // Fall back to trying to find the launcher via the .desktop file
    return itemInModel(desktopFileFromPackageName(m_directories, packageName));
}

QVariant LauncherModel::launcherPos(const QString &path)
{
    QString key = m_launcherOrderPrefix + path;

    if (m_launcherSettings.contains(key)) {
        return m_launcherSettings.value(key);
    }

    // fall back to vendor configuration if the user hasn't specified a location
    return m_globalSettings.value(key);
}

LauncherItem *LauncherModel::addItemIfValid(const QString &path)
{
    LAUNCHER_DEBUG("Creating LauncherItem for desktop entry" << path);
    LauncherItem *item = new LauncherItem(path, this);

    bool isValid = item->isValid();
    bool shouldDisplay = item->shouldDisplay() && displayCategory(item);

    item->setIsBlacklisted(isBlacklisted(item));

    if (isValid && shouldDisplay) {
        addItem(item);
    } else if (isValid) {
        m_hiddenLaunchers.append(item);
        item = nullptr;
    } else {
        LAUNCHER_DEBUG("Item" << path << (!isValid ? "is not valid" : "should not be displayed"));
        delete item;
        item = nullptr;
    }

    return item;
}

bool LauncherModel::displayCategory(LauncherItem *item) const
{
    bool display = m_categories.isEmpty();

    foreach (const QString &category, item->desktopCategories()) {
        if (m_categories.contains(category)) {
            display = true;
            break;
        }
    }

    return display;
}

void LauncherModel::setTemporary(LauncherItem *item)
{
    if (!item->isTemporary()) {
        item->setIsTemporary(true);
        m_temporaryLaunchers.append(item);
    }
}

void LauncherModel::unsetTemporary(LauncherItem *item)
{
    if (item->isTemporary()) {
        item->setIsTemporary(false);
        m_temporaryLaunchers.removeOne(item);
    }
}

LauncherItem *LauncherModel::temporaryItemToReplace()
{
    LauncherItem *item = nullptr;
    if (m_temporaryLaunchers.count() == 1) {
        // Only one item. It must be this.
        item = m_temporaryLaunchers.first();
    } else {
        foreach (LauncherItem *tempItem, m_temporaryLaunchers) {
            if (!tempItem->isUpdating()) {
                if (!item) {
                    // Pick the finished item.
                    item = tempItem;
                } else {
                    // Give up if many items have finished.
                    item = nullptr;
                    break;
                }
            }
        }
    }
    return item;
}

bool LauncherModel::isBlacklisted(LauncherItem *item) const
{
    return item && m_blacklistedApplications.contains(item->filePath());
}
