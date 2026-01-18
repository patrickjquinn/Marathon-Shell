#include "desktopfileparser.h"
#include <QFile>
#include <QTextStream>
#include <QDir>
#include <QFileInfo>
#include <QDebug>
#include <QRegularExpression>

DesktopFileParser::DesktopFileParser(QObject *parent)
    : QObject(parent) {}

QVariantList DesktopFileParser::scanApplications(const QStringList &searchPaths) {

    return scanApplications(searchPaths, false);
}

QVariantList DesktopFileParser::scanApplications(const QStringList &searchPaths,
                                                 bool               filterMobileFriendly) {
    QVariantList apps;

    qDebug() << "[DesktopFileParser] Scanning with mobile filter:" << filterMobileFriendly;

    for (const QString &path : searchPaths) {
        QDir dir(path);
        if (!dir.exists()) {
            qDebug() << "[DesktopFileParser] Directory does not exist:" << path;
            continue;
        }

        QStringList filters;
        filters << "*.desktop";
        QFileInfoList desktopFiles = dir.entryInfoList(filters, QDir::Files);

        qDebug() << "[DesktopFileParser] Found" << desktopFiles.count() << "desktop files in"
                 << path;

        for (const QFileInfo &fileInfo : desktopFiles) {
            QVariantMap app = parseDesktopFile(fileInfo.absoluteFilePath());
            if (!app.isEmpty()) {

                if (filterMobileFriendly) {
                    if (isMobileFriendly(app)) {
                        apps.append(app);
                        qDebug() << "[DesktopFileParser] ✓ Mobile-friendly:"
                                 << app["name"].toString();
                    } else {
                        qDebug() << "[DesktopFileParser] ✗ Not mobile-friendly (filtered):"
                                 << app["name"].toString();
                    }
                } else {
                    apps.append(app);
                }
            }
        }
    }

    qDebug() << "[DesktopFileParser] Total apps found:" << apps.count()
             << "(filtered:" << filterMobileFriendly << ")";
    return apps;
}

QVariantMap DesktopFileParser::parseDesktopFile(const QString &filePath) {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[DesktopFileParser] Cannot open file:" << filePath;
        return QVariantMap();
    }

    QTextStream in(&file);
    QVariantMap app;
    bool        inDesktopEntry = false;

    app["type"]        = "native";
    app["desktopFile"] = filePath;
    app["noDisplay"]   = false;
    app["hidden"]      = false;
    app["terminal"]    = false;

    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();

        if (line == "[Desktop Entry]") {
            inDesktopEntry = true;
            continue;
        }

        if (line.startsWith('[') && line.endsWith(']')) {
            inDesktopEntry = false;
            continue;
        }

        if (!inDesktopEntry || line.isEmpty() || line.startsWith('#')) {
            continue;
        }

        int eqPos = line.indexOf('=');
        if (eqPos < 0)
            continue;

        QString key   = line.left(eqPos).trimmed();
        QString value = line.mid(eqPos + 1).trimmed();

        if (key == "Name") {
            app["name"] = value;
        } else if (key == "Comment" || (key == "GenericName" && !app.contains("comment"))) {
            app["comment"] = value;
        } else if (key == "Icon") {
            app["icon"] = resolveIconPath(value);
        } else if (key == "Exec") {
            app["exec"] = cleanExecLine(value);
        } else if (key == "Terminal") {
            app["terminal"] = (value.toLower() == "true");
        } else if (key == "Categories") {
            app["categories"] = value.split(';', Qt::SkipEmptyParts);
        } else if (key == "NoDisplay") {
            app["noDisplay"] = (value.toLower() == "true");
        } else if (key == "Hidden") {
            app["hidden"] = (value.toLower() == "true");
        } else if (key == "Type") {
            if (value != "Application") {
                return QVariantMap();
            }
        } else if (key == "X-Purism-FormFactor") {

            app["purismFormFactor"] = value.split(';', Qt::SkipEmptyParts);
        } else if (key == "X-KDE-FormFactors") {

            app["kdeFormFactors"] = value.split(';', Qt::SkipEmptyParts);
        }
    }

    if (!app.contains("name") || !app.contains("exec") || app["noDisplay"].toBool() ||
        app["hidden"].toBool()) {
        return QVariantMap();
    }

    QFileInfo fileInfo(filePath);
    QString   id = fileInfo.completeBaseName();
    app["id"]    = id;

    file.close();
    return app;
}

QString DesktopFileParser::resolveIconPath(const QString &iconName) {
    const auto it = m_iconCache.constFind(iconName);
    if (it != m_iconCache.constEnd())
        return it.value();

    if (iconName.isEmpty()) {
        const QString fallback = "grid";
        m_iconCache.insert(iconName, fallback);
        return fallback;
    }

    if (iconName.startsWith('/')) {
        if (QFile::exists(iconName)) {
            m_iconCache.insert(iconName, iconName);
            return iconName;
        }
        const QString fallback = "grid";
        m_iconCache.insert(iconName, fallback);
        return fallback;
    }

    if (iconName.endsWith(".svg") || iconName.endsWith(".png") || iconName.endsWith(".xpm") ||
        iconName.endsWith(".jpg")) {
        if (QFile::exists(iconName)) {
            m_iconCache.insert(iconName, iconName);
            return iconName;
        }
    }

    QStringList searchPaths = {

        QDir::homePath() + "/.local/share/icons/hicolor/scalable/apps/",
        "/usr/share/icons/hicolor/scalable/apps/",
        "/usr/share/icons/hicolor/scalable/devices/",
        "/usr/share/icons/hicolor/scalable/places/",
        "/usr/share/icons/hicolor/scalable/categories/",
        "/usr/share/icons/PiXtrix/scalable/apps/",
        "/usr/share/icons/PiXtrix/scalable/categories/",
        "/usr/share/icons/PiXtrix/scalable/devices/",
        "/usr/share/icons/PiXtrix/scalable/places/",
        "/usr/share/icons/Adwaita/scalable/apps/",
        "/usr/share/icons/Adwaita/scalable/categories/",
        "/usr/share/icons/Adwaita/scalable/devices/",
        "/usr/share/icons/Adwaita/scalable/places/",
        "/usr/share/icons/gnome/scalable/apps/",
        "/usr/share/icons/gnome/scalable/categories/",
        "/usr/share/icons/gnome/scalable/devices/",
        "/usr/share/icons/gnome/scalable/places/",
        QDir::homePath() + "/.local/share/flatpak/exports/share/icons/hicolor/scalable/apps/",
        "/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps/",

        QDir::homePath() + "/.local/share/icons/hicolor/512x512/apps/",
        "/usr/share/icons/hicolor/512x512/apps/",
        QDir::homePath() + "/.local/share/flatpak/exports/share/icons/hicolor/512x512/apps/",
        "/var/lib/flatpak/exports/share/icons/hicolor/512x512/apps/",

        QDir::homePath() + "/.local/share/icons/hicolor/256x256/apps/",
        "/usr/share/icons/hicolor/256x256/apps/",
        QDir::homePath() + "/.local/share/flatpak/exports/share/icons/hicolor/256x256/apps/",
        "/var/lib/flatpak/exports/share/icons/hicolor/256x256/apps/",

        QDir::homePath() + "/.local/share/icons/hicolor/128x128/apps/",
        "/usr/share/icons/hicolor/128x128/apps/",
        "/usr/share/icons/hicolor/128x128/devices/",
        "/usr/share/icons/hicolor/128x128/places/",
        QDir::homePath() + "/.local/share/flatpak/exports/share/icons/hicolor/128x128/apps/",
        "/var/lib/flatpak/exports/share/icons/hicolor/128x128/apps/",

        "/usr/share/icons/PiXtrix/96x96/apps/",
        "/usr/share/icons/PiXtrix/96x96/categories/",
        "/usr/share/icons/PiXtrix/96x96/devices/",
        "/usr/share/icons/PiXtrix/96x96/places/",
        "/usr/share/icons/PiXtrix/64x64/apps/",
        "/usr/share/icons/PiXtrix/64x64/categories/",
        "/usr/share/icons/PiXtrix/64x64/devices/",
        "/usr/share/icons/PiXtrix/64x64/places/",
        "/usr/share/icons/PiXtrix/48x48/apps/",
        "/usr/share/icons/PiXtrix/48x48/categories/",
        "/usr/share/icons/PiXtrix/48x48/devices/",
        "/usr/share/icons/PiXtrix/48x48/places/",

        "/usr/share/icons/AdwaitaLegacy/48x48/legacy/",
        "/usr/share/icons/AdwaitaLegacy/48x48/devices/",
        "/usr/share/icons/AdwaitaLegacy/48x48/places/",
        "/usr/share/icons/AdwaitaLegacy/32x32/legacy/",
        "/usr/share/icons/AdwaitaLegacy/32x32/devices/",
        "/usr/share/icons/AdwaitaLegacy/32x32/places/",
        "/usr/share/icons/AdwaitaLegacy/24x24/legacy/",
        "/usr/share/icons/AdwaitaLegacy/24x24/devices/",
        "/usr/share/icons/AdwaitaLegacy/24x24/places/",

        "/var/lib/snapd/desktop/icons/",

        "/usr/share/icons/hicolor/64x64/apps/",
        "/usr/share/icons/hicolor/64x64/devices/",
        "/usr/share/icons/hicolor/64x64/places/",
        QDir::homePath() + "/.local/share/icons/hicolor/64x64/apps/",

        "/usr/share/icons/hicolor/48x48/apps/",
        "/usr/share/icons/hicolor/48x48/devices/",
        "/usr/share/icons/hicolor/48x48/places/",
        "/usr/share/icons/hicolor/32x32/apps/",
        "/usr/share/icons/hicolor/32x32/devices/",
        "/usr/share/icons/hicolor/32x32/places/",
        "/usr/share/pixmaps/"};

    QStringList extensions = {".png", ".svg", ".xpm", ".jpg", ""};

    for (const QString &basePath : searchPaths) {
        for (const QString &ext : extensions) {
            QString fullPath = basePath + iconName + ext;
            if (QFile::exists(fullPath)) {
                qDebug() << "[DesktopFileParser] Found icon:" << fullPath;

                m_iconCache.insert(iconName, fullPath);
                return fullPath;
            }
        }
    }

    qDebug() << "[DesktopFileParser] Icon not found:" << iconName << ", using fallback";
    const QString fallback = "layout-grid";
    m_iconCache.insert(iconName, fallback);
    return fallback;
}

QString DesktopFileParser::cleanExecLine(const QString &exec) {

    QString            cleaned = exec;
    QRegularExpression re("%[fFuUdDnNickvm]");
    cleaned.remove(re);
    cleaned = cleaned.trimmed();

    QStringList windowFlags = {"--new-window", "-new-window",    "--new-tab",
                               "-new-tab",     "--new-instance", "-new-instance"};

    for (const QString &flag : windowFlags) {
        if (cleaned.contains(flag)) {
            cleaned.remove(flag);
            cleaned = cleaned.trimmed();
            qInfo() << "[DesktopFileParser] *** REMOVED window control flag:" << flag
                    << "to enable compositor embedding";
        }
    }

    if (cleaned.startsWith("gapplication launch ")) {
        QString     appId = cleaned.mid(20).trimmed();

        QStringList parts = appId.split('.');
        if (parts.size() >= 2) {
            QString binaryName = parts.last().toLower();

            if (parts.size() >= 3) {
                QString vendor = parts[parts.size() - 2].toLower();
                binaryName     = vendor + "-" + binaryName;
            }

            qInfo() << "[DesktopFileParser] *** CONVERTING gapplication launch" << appId
                    << "to binary:" << binaryName;
            return binaryName;
        } else {
            qWarning() << "[DesktopFileParser] Failed to parse gapplication app ID:" << appId;
            return cleaned;
        }
    }

    if (cleaned.contains("--gapplication-service")) {
        qDebug() << "[DesktopFileParser] Skipping gapplication service:" << cleaned;
        return QString();
    }

    if (cleaned.startsWith("flatpak run ")) {
        qDebug() << "[DesktopFileParser] Detected Flatpak app, adding Wayland permissions:"
                 << cleaned;

        cleaned = "FLATPAK:" + cleaned;
        return cleaned;
    }

    if (cleaned.startsWith("snap run ") || cleaned.startsWith("/snap/bin/")) {
        qDebug() << "[DesktopFileParser] Detected Snap app:" << cleaned;

        cleaned = "SNAP:" + cleaned;
        return cleaned;
    }

    if (cleaned.startsWith('/')) {
        QStringList parts = cleaned.split(' ', Qt::SkipEmptyParts);
        if (!parts.isEmpty()) {
            QString   binaryPath = parts.first();
            QFileInfo fileInfo(binaryPath);
            parts[0] = fileInfo.fileName();
            cleaned  = parts.join(' ');
            qDebug() << "[DesktopFileParser] Simplified absolute path to:" << cleaned;
        }
    }

    return cleaned;
}

bool DesktopFileParser::isMobileFriendly(const QVariantMap &app) {

    if (app.contains("purismFormFactor")) {
        QStringList formFactors = app["purismFormFactor"].toStringList();
        for (const QString &factor : formFactors) {
            if (factor.contains("Mobile", Qt::CaseInsensitive)) {
                qDebug() << "[DesktopFileParser]   Mobile-friendly via X-Purism-FormFactor:"
                         << factor;
                return true;
            }
        }
    }

    if (app.contains("kdeFormFactors")) {
        QStringList formFactors = app["kdeFormFactors"].toStringList();
        for (const QString &factor : formFactors) {
            if (factor.contains("handset", Qt::CaseInsensitive) ||
                factor.contains("phone", Qt::CaseInsensitive)) {
                qDebug() << "[DesktopFileParser]   Mobile-friendly via X-KDE-FormFactors:"
                         << factor;
                return true;
            }
        }
    }

    return false;
}
