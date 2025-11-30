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
    // Default: don't filter (for backwards compatibility)
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
                // Apply mobile-friendly filter if requested
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
                return QVariantMap(); // Not an application
            }
        } else if (key == "X-Purism-FormFactor") {
            // Phosh/Purism form factor specification
            app["purismFormFactor"] = value.split(';', Qt::SkipEmptyParts);
        } else if (key == "X-KDE-FormFactors") {
            // KDE form factor specification
            app["kdeFormFactors"] = value.split(';', Qt::SkipEmptyParts);
        }
    }

    // Validate required fields
    if (!app.contains("name") || !app.contains("exec") || app["noDisplay"].toBool() ||
        app["hidden"].toBool()) {
        return QVariantMap();
    }

    // Generate ID from filename (use completeBaseName to keep full name like "org.gnome.Calendar")
    QFileInfo fileInfo(filePath);
    QString   id = fileInfo.completeBaseName(); // Remove only .desktop extension, keep dots
    app["id"]    = id;

    file.close();
    return app;
}

QString DesktopFileParser::resolveIconPath(const QString &iconName) {
    if (iconName.isEmpty()) {
        return "qrc:/images/icons/lucide/grid.svg";
    }

    // If it's already an absolute path, use it
    if (iconName.startsWith('/')) {
        if (QFile::exists(iconName)) {
            return "file://" + iconName;
        }
        return "qrc:/images/icons/lucide/grid.svg";
    }

    // If it already has an extension, check if it exists
    if (iconName.endsWith(".svg") || iconName.endsWith(".png") || iconName.endsWith(".xpm") ||
        iconName.endsWith(".jpg")) {
        if (QFile::exists(iconName)) {
            return "file://" + iconName;
        }
    }

    // Search common icon paths
    QStringList searchPaths = {"/usr/share/pixmaps/",
                               "/usr/share/icons/hicolor/scalable/apps/",
                               "/usr/share/icons/hicolor/48x48/apps/",
                               "/usr/share/icons/hicolor/64x64/apps/",
                               "/usr/share/icons/hicolor/128x128/apps/",
                               "/usr/share/icons/hicolor/256x256/apps/",
                               "~/.local/share/icons/hicolor/scalable/apps/",
                               "~/.local/share/icons/hicolor/48x48/apps/"};

    QStringList extensions = {".svg", ".png", ".xpm", ""};

    for (const QString &basePath : searchPaths) {
        QString expandedPath = basePath;
        if (expandedPath.startsWith('~')) {
            expandedPath.replace(0, 1, QDir::homePath());
        }

        for (const QString &ext : extensions) {
            QString fullPath = expandedPath + iconName + ext;
            if (QFile::exists(fullPath)) {
                qDebug() << "[DesktopFileParser] Found icon:" << fullPath;
                return "file://" + fullPath;
            }
        }
    }

    qDebug() << "[DesktopFileParser] Icon not found:" << iconName << ", using fallback";
    return "qrc:/images/icons/lucide/grid.svg";
}

QString DesktopFileParser::cleanExecLine(const QString &exec) {
    // Remove field codes like %f, %F, %u, %U, etc.
    QString            cleaned = exec;
    QRegularExpression re("%[fFuUdDnNickvm]");
    cleaned.remove(re);
    cleaned = cleaned.trimmed();

    // CRITICAL FIX: Remove flags that cause apps to open in separate windows
    // These flags bypass the Wayland compositor and open in host/parent compositor
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

    // Convert "gapplication launch org.gnome.AppName" to direct binary execution
    // This bypasses D-Bus activation which would launch apps in host session
    if (cleaned.startsWith("gapplication launch ")) {
        QString appId = cleaned.mid(20).trimmed(); // Extract app ID after "gapplication launch "

        // Convert app ID to binary name: org.gnome.Weather -> gnome-weather
        QStringList parts = appId.split('.');
        if (parts.size() >= 2) {
            QString binaryName = parts.last().toLower();
            // Add vendor prefix if it exists (e.g., gnome-, kde-)
            if (parts.size() >= 3) {
                QString vendor = parts[parts.size() - 2].toLower();
                binaryName     = vendor + "-" + binaryName;
            }

            qInfo() << "[DesktopFileParser] *** CONVERTING gapplication launch" << appId
                    << "to binary:" << binaryName;
            return binaryName;
        } else {
            qWarning() << "[DesktopFileParser] Failed to parse gapplication app ID:" << appId;
            return cleaned; // Return as-is if we can't parse
        }
    }

    // Handle --gapplication-service flag (background services, should be filtered out by NoDisplay)
    if (cleaned.contains("--gapplication-service")) {
        qDebug() << "[DesktopFileParser] Skipping gapplication service:" << cleaned;
        return QString(); // Return empty to filter out
    }

    // Handle Flatpak applications
    if (cleaned.startsWith("flatpak run ")) {
        qDebug() << "[DesktopFileParser] Detected Flatpak app, adding Wayland permissions:"
                 << cleaned;
        // Note: Marathon compositor socket name and path will be added at launch time
        // For now, just mark it for special handling
        cleaned = "FLATPAK:" + cleaned;
        return cleaned;
    }

    // Handle Snap applications
    if (cleaned.startsWith("snap run ") || cleaned.startsWith("/snap/bin/")) {
        qDebug() << "[DesktopFileParser] Detected Snap app:" << cleaned;
        // Note: Snap wayland interface must be connected: snap connect APP:wayland :wayland
        // Mark for special handling
        cleaned = "SNAP:" + cleaned;
        return cleaned;
    }

    // Strip absolute paths to just binary name (for better compatibility)
    // /usr/bin/firefox -> firefox
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
    // Check X-Purism-FormFactor (Phosh standard)
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

    // Check X-KDE-FormFactors (KDE standard)
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

    // If no form factor is specified, consider it desktop-only
    return false;
}
