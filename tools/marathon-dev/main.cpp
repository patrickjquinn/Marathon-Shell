#include <QCoreApplication>
#include <QCommandLineParser>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QTextStream>
#include "marathonapppackager.h"
#include "marathonappverifier.h"
#include "marathonappinstaller.h"
#include "marathonappregistry.h"
#include "marathonappscanner.h"

void printSuccess(const QString &message) {
    QTextStream out(stdout);
    out << "\033[32m\033[0m " << message << Qt::endl;
}

void printError(const QString &message) {
    QTextStream err(stderr);
    err << "\033[31m\033[0m " << message << Qt::endl;
}

void printInfo(const QString &message) {
    QTextStream out(stdout);
    out << "\033[34mℹ\033[0m " << message << Qt::endl;
}

int packageCommand(const QStringList &args) {
    if (args.size() < 3) {
        printError("Usage: marathon-dev package <app-directory> [output-file]");
        return 1;
    }

    const QString &appDir = args.at(2);
    QString        outputFile;

    if (args.size() >= 4) {
        outputFile = args.at(3);
    } else {

        QFileInfo dirInfo(appDir);
        QString   appDirName = dirInfo.fileName();
        outputFile           = appDirName + ".marathon";
    }

    printInfo("Packaging app from: " + appDir);
    printInfo("Output file: " + outputFile);

    MarathonAppPackager packager;

    if (packager.createPackage(appDir, outputFile)) {
        printSuccess("Package created successfully: " + outputFile);

        QFileInfo packageInfo(outputFile);
        qint64    sizeKB = packageInfo.size() / 1024;
        printInfo(QString("Package size: %1 KB").arg(sizeKB));

        return 0;
    } else {
        printError("Failed to create package: " + packager.lastError());
        return 1;
    }
}

// minisign's own default secret key location.
QString defaultSecretKey() {
    return QDir::homePath() + "/.minisign/minisign.key";
}

int signCommand(const QStringList &args) {
    if (args.size() < 3) {
        printError("Usage: marathon-dev sign <package-file> [secret-key]");
        return 1;
    }

    const QString &packagePath = args.at(2);
    const QString  secretKey   = args.size() >= 4 ? args.at(3) : defaultSecretKey();

    printInfo("Signing package: " + packagePath);
    printInfo("Using minisign key: " + secretKey);

    MarathonAppVerifier verifier;
    if (!verifier.signPackage(packagePath, secretKey)) {
        printError("Failed to sign package: " + verifier.lastError());
        printInfo("Create a key with: minisign -G");
        return 1;
    }
    printSuccess("Signature saved to: " + packagePath + ".minisig");
    return 0;
}

int verifyCommand(const QStringList &args) {
    if (args.size() < 3) {
        printError("Usage: marathon-dev verify <package-file>");
        return 1;
    }

    const QString &packagePath = args.at(2);
    printInfo("Verifying: " + packagePath);

    MarathonAppVerifier                           verifier;
    const MarathonAppVerifier::VerificationResult result = verifier.verifyPackage(packagePath);
    switch (result) {
        case MarathonAppVerifier::Valid:
            printSuccess("Signed by trusted key " + verifier.signerKeyId());
            return 0;
        case MarathonAppVerifier::AllowedUnsigned:
            printInfo("Unsigned, accepted only because MARATHON_ALLOW_UNSIGNED=1");
            return 0;
        case MarathonAppVerifier::SignatureMissing:
            printError(verifier.lastError());
            printInfo("Sign it with: marathon-dev sign " + packagePath);
            return 1;
        case MarathonAppVerifier::UntrustedKey:
            printError(verifier.lastError());
            printInfo("Trusted keys live in: " + MarathonAppVerifier::trustedKeyDirs().join(", "));
            return 1;
        default: printError(verifier.lastError()); return 1;
    }
}

int installCommand(const QStringList &args) {
    if (args.size() < 3) {
        printError("Usage: marathon-dev install <package-file|app-directory> "
                   "[--approve-permissions]");
        return 1;
    }

    const QString &path = args.at(2);
    QFileInfo      pathInfo(path);
    if (!pathInfo.isDir() && !path.endsWith(".marathon")) {
        printError("Unknown file type. Expected directory or .marathon package");
        return 1;
    }

    printInfo("Installing: " + path);

    MarathonAppRegistry  registry;
    MarathonAppScanner   scanner(&registry);
    MarathonAppInstaller installer(&registry, &scanner);
    QObject::connect(&installer, &MarathonAppInstaller::installFailed,
                     [](const QString &, const QString &error) { printError(error); });
    QObject::connect(&installer, &MarathonAppInstaller::installPlanned,
                     [](const QString &, const QVariantMap &plan) {
                         const QVariantList permissions = plan.value("permissions").toList();
                         printInfo(permissions.isEmpty() ? "Permissions: none" : "Permissions:");
                         for (const QVariant &permission : permissions) {
                             const QVariantMap d = permission.toMap();
                             printInfo(QString("  %1 %2: %3")
                                           .arg(d.value("sensitive").toBool() ? "!" : " ",
                                                d.value("label").toString(),
                                                d.value("detail").toString()));
                         }
                     });
    QStringList held;
    QObject::connect(&installer, &MarathonAppInstaller::installHeld,
                     [&held](const QString &, const QVariantMap &plan) {
                         held = plan.value("added").toStringList();
                     });

    const auto install = [&](const QStringList &approved) {
        return pathInfo.isDir() ? installer.installFromDirectory(path, approved) :
                                  installer.installFromPackage(path, approved);
    };
    bool success = install({});
    if (!success && !held.isEmpty()) {
        printError("This update asks for new permissions: " + held.join(", "));
        if (!args.contains("--approve-permissions")) {
            printInfo("Re-run with --approve-permissions to allow them");
            return 1;
        }
        printInfo("Allowed by --approve-permissions");
        success = install(held);
    }

    if (success) {
        printSuccess("App installed successfully");
        printInfo("Install location: " + installer.getInstallDirectory());
        return 0;
    } else {
        printError("Installation failed");
        return 1;
    }
}

int initCommand(const QStringList &args) {
    if (args.size() < 3) {
        printError("Usage: marathon-dev init <app-name>");
        return 1;
    }

    const QString &appName = args.at(2);
    QString        appId   = appName.toLower().replace(" ", "-");

    QDir           dir;
    if (!dir.mkdir(appId)) {
        printError("Failed to create directory: " + appId);
        return 1;
    }

    dir.cd(appId);
    dir.mkdir("pages");
    dir.mkdir("components");
    dir.mkdir("assets");

    QJsonObject manifest;
    manifest["id"]              = appId;
    manifest["name"]            = appName;
    manifest["version"]         = "1.0.0";
    manifest["entryPoint"]      = appId.replace("-", "") + "App.qml";
    manifest["icon"]            = "assets/icon.svg";
    manifest["author"]          = "Your Name";
    manifest["permissions"]     = QJsonArray();
    manifest["minShellVersion"] = "1.0.0";
    manifest["protected"]       = false;

    QFile manifestFile(appId + "/manifest.json");
    if (manifestFile.open(QIODevice::WriteOnly)) {
        manifestFile.write(QJsonDocument(manifest).toJson(QJsonDocument::Indented));
        manifestFile.close();
    }

    QString appFileName = appId.replace("-", "");
    appFileName[0]      = appFileName[0].toUpper();
    appFileName += "App.qml";

    QString qmlTemplate = QString(R"(import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

ApplicationWindow {
    appId: "%2"

    initialPage: Component {
        Page {
            PageHeader {
                title: "%1"
            }

            ViewPlaceholder {
                enabled: true
                text: "Welcome to %1!"
            }
        }
    }
}
)")
                              .arg(appName, manifest["id"].toString());

    QFile   qmlFile(appId + "/" + appId.replace("-", "") + "App.qml");
    if (qmlFile.open(QIODevice::WriteOnly)) {
        qmlFile.write(qmlTemplate.toUtf8());
        qmlFile.close();
    }

    QString qmldirContent = QString("module %1\n").arg(appId);
    QFile   qmldirFile(appId + "/qmldir");
    if (qmldirFile.open(QIODevice::WriteOnly)) {
        qmldirFile.write(qmldirContent.toUtf8());
        qmldirFile.close();
    }

    QString iconSVG = R"(<?xml version="1.0" encoding="UTF-8"?>
<svg width="512" height="512" viewBox="0 0 512 512" xmlns="http: 
    <rect width="512" height="512" fill="#4CAF50" rx="100"/>
    <text x="256" y="320" font-family="Arial" font-size="200" fill="white" text-anchor="middle">A</text>
</svg>)";

    QFile   iconFile(appId + "/assets/icon.svg");
    if (iconFile.open(QIODevice::WriteOnly)) {
        iconFile.write(iconSVG.toUtf8());
        iconFile.close();
    }

    printSuccess("App created: " + appId);
    printInfo("Next steps:");
    printInfo("  1. cd " + appId);
    printInfo("  2. Edit manifest.json with your app details");
    printInfo("  3. Implement your app in " + appId.replace("-", "") + "App.qml");
    printInfo("  4. Package with: marathon-dev package .");
    printInfo("  5. Sign it with: marathon-dev sign <package>.marathon");

    return 0;
}

void printHelp() {
    QTextStream out(stdout);
    out << "Marathon Developer Tool - Build and package Marathon apps\n\n";
    out << "Usage: marathon-dev <command> [options]\n\n";
    out << "Commands:\n";
    out << "  init <app-name>              Create a new app from template\n";
    out << "  package <app-dir> [output]   Package an app into .marathon file\n";
    out << "  sign <package> [secret-key]  Sign a package with a minisign key\n";
    out << "  verify <package>             Check a package's signature\n";
    out << "  install <package|app-dir> [--approve-permissions]\n";
    out << "                               Install an app locally\n";
    out << "\n";
    out << "Examples:\n";
    out << "  marathon-dev init my-awesome-app\n";
    out << "  marathon-dev package ./my-app\n";
    out << "  marathon-dev sign my-app.marathon ~/.minisign/minisign.key\n";
    out << "  marathon-dev verify my-app.marathon\n";
    out << "  marathon-dev install my-app.marathon\n";
    out << Qt::endl;
}

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName("marathon-dev");
    QCoreApplication::setApplicationVersion("1.0.0");

    QStringList args = QCoreApplication::arguments();

    if (args.size() < 2) {
        printHelp();
        return 0;
    }

    const QString &command = args.at(1);

    if (command == "init") {
        return initCommand(args);
    } else if (command == "package") {
        return packageCommand(args);
    } else if (command == "sign") {
        return signCommand(args);
    } else if (command == "verify") {
        return verifyCommand(args);
    } else if (command == "install") {
        return installCommand(args);
    } else if (command == "help" || command == "--help" || command == "-h") {
        printHelp();
        return 0;
    } else {
        printError("Unknown command: " + command);
        printInfo("Run 'marathon-dev help' for usage information");
        return 1;
    }
}
