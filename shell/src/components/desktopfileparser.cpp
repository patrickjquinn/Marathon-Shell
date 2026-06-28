#include "desktopfileparser.h"
#include <QFile>
#include <QTextStream>
#include <QDir>
#include <QFileInfo>
#include <QDebug>
#include <QRegularExpression>
#include <QSet>

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
                        qDebug() << "[DesktopFileParser] Mobile-friendly:"
                                 << app["name"].toString();
                    } else {
                        qDebug() << "[DesktopFileParser] Not mobile-friendly (filtered):"
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
        } else if (key == "X-Flatpak") {
            app["flatpakRef"] = value;
        }
    }

    if (!app.contains("name") || !app.contains("exec") || app["noDisplay"].toBool() ||
        app["hidden"].toBool()) {
        return QVariantMap();
    }

    // Marathon is Wayland-only — there's no X server, so X-only apps
    // would just spin forever on the loading splash. Skip them at
    // discovery time so they never reach the home grid.
    static const QSet<QString> kX11OnlyBinaries{
        "xterm",    "uxterm",  "xclock", "xcalc", "xeyes",  "xlogo",    "xev",    "xinit",   "xrdb",
        "xfontsel", "xkbcomp", "xkill",  "xset",  "xsetbg", "xsetroot", "xrandr", "xdpyinfo"};
    const QStringList execTokens = app["exec"].toString().split(' ', Qt::SkipEmptyParts);
    QString           binaryName;
    for (const QString &tok : execTokens) {
        if (tok.startsWith('-'))
            continue;
        binaryName = QFileInfo(tok).fileName();
        break;
    }
    if (kX11OnlyBinaries.contains(binaryName)) {
        qDebug() << "[DesktopFileParser] Skipping X11-only app:" << binaryName;
        return QVariantMap();
    }

    QFileInfo fileInfo(filePath);
    QString   id = fileInfo.completeBaseName();
    app["id"]    = id;

    if (app.value("exec").toString().startsWith(QStringLiteral("FLATPAK:"))) {
        app["type"] = "flatpak";

        if (!app.contains("flatpakRef")) {
            // Older flatpak exports omit X-Flatpak; the ref is the last
            // non-option token of the Exec line.
            const QStringList tokens = app["exec"].toString().split(' ', Qt::SkipEmptyParts);
            for (auto it = tokens.crbegin(); it != tokens.crend(); ++it) {
                if (!it->startsWith('-') && it->contains('.')) {
                    app["flatpakRef"] = *it;
                    break;
                }
            }
        }
    }

    file.close();
    return app;
}

QString DesktopFileParser::resolveIconPath(const QString &iconName) {
    const auto it = m_iconCache.constFind(iconName);
    if (it != m_iconCache.constEnd())
        return it.value();

    static const QString kIconFallback = QStringLiteral("layout-grid");

    if (iconName.isEmpty()) {
        m_iconCache.insert(iconName, kIconFallback);
        return kIconFallback;
    }

    if (iconName.startsWith('/')) {
        if (QFile::exists(iconName)) {
            m_iconCache.insert(iconName, iconName);
            return iconName;
        }
        m_iconCache.insert(iconName, kIconFallback);
        return kIconFallback;
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

    QStringList tokens = cleaned.split(' ', Qt::SkipEmptyParts);
    for (const QString &flag : windowFlags) {
        if (tokens.removeAll(flag) > 0) {
            qInfo() << "[DesktopFileParser] *** REMOVED window control flag:" << flag
                    << "to enable compositor embedding";
        }
    }
    cleaned = tokens.join(' ');

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

    // GNOME/freedesktop "Mobile" category — used by post-GTK4 apps that
    // intentionally pass mobile QA (Calls, Chats, Portfolio, etc.).
    if (app.contains("categories")) {
        QStringList categories = app["categories"].toStringList();
        for (const QString &cat : categories) {
            if (cat.compare("Mobile", Qt::CaseInsensitive) == 0 ||
                cat.compare("Phone", Qt::CaseInsensitive) == 0) {
                qDebug() << "[DesktopFileParser]   Mobile-friendly via Categories:" << cat;
                return true;
            }
        }
    }

    // Curated allowlist — GTK4/libadwaita and KDE Plasma apps that ship as
    // adaptive by default but don't bother declaring the hint. Keyed on the
    // desktop file basename (= app id) so themes/forks don't drift it.
    static const QSet<QString> kCuratedAdaptive{
        // GNOME Circle / adaptive-by-default
        "org.gnome.Calendar",
        "org.gnome.Calls",
        "org.gnome.Chess",
        "org.gnome.Contacts",
        "org.gnome.Loupe",
        "org.gnome.Maps",
        "org.gnome.Music",
        "org.gnome.Papers",
        "org.gnome.Snapshot",
        "org.gnome.TextEditor",
        "org.gnome.Weather",
        "org.gnome.clocks",
        "org.gnome.font-viewer",
        // Phosh / Mobian first-party
        "sm.puri.Chatty",
        "sm.puri.Phosh",
        "org.sigxcpu.Phosh",
        // KDE Plasma Mobile
        "org.kde.angelfish",
        "org.kde.calindori",
        "org.kde.kalk",
        "org.kde.kasts",
        "org.kde.kclock",
        "org.kde.koko",
        "org.kde.neochat",
        "org.kde.tokodon",
        // Useful daily-drivers known to work in 720 px / single-column
        "org.gnome.Console",
        "io.github.tchx84.Flatseal",
        "page.codeberg.libre_menteur.LibreMenteur",
    };
    const QString id = QFileInfo(app.value("desktopFile").toString()).completeBaseName();
    if (kCuratedAdaptive.contains(id)) {
        qDebug() << "[DesktopFileParser]   Mobile-friendly via curated allowlist:" << id;
        return true;
    }

    return false;
}
