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
#include "../../shell/src/marathonapppackager.h"
#include "../../shell/src/marathonappverifier.h"
#include "../../shell/src/marathonappinstaller.h"
#include "../../shell/src/marathonappregistry.h"
#include "../../shell/src/marathonappscanner.h"

void printSuccess(const QString &message) {
    QTextStream out(stdout);
    out << "\033[32m✓\033[0m " << message << Qt::endl;
}

void printError(const QString &message) {
    QTextStream err(stderr);
    err << "\033[31m✗\033[0m " << message << Qt::endl;
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

    QString appDir = args.at(2);
    QString outputFile;

    if (args.size() >= 4) {
        outputFile = args.at(3);
    } else {
        // Generate output filename from app directory
        QFileInfo dirInfo(appDir);
        QString   appDirName = dirInfo.fileName();
        outputFile           = appDirName + ".marathon";
    }

    printInfo("Packaging app from: " + appDir);
    printInfo("Output file: " + outputFile);

    MarathonAppPackager packager;

    if (packager.createPackage(appDir, outputFile)) {
        printSuccess("Package created successfully: " + outputFile);

        // Show package info
        QFileInfo packageInfo(outputFile);
        qint64    sizeKB = packageInfo.size() / 1024;
        printInfo(QString("Package size: %1 KB").arg(sizeKB));

        return 0;
    } else {
        printError("Failed to create package: " + packager.lastError());
        return 1;
    }
}

int signCommand(const QStringList &args) {
    if (args.size() < 3) {
        printError("Usage: marathon-dev sign <app-directory> [key-id]");
        return 1;
    }

    QString appDir = args.at(2);
    QString keyId;

    if (args.size() >= 4) {
        keyId = args.at(3);
    }

    QString manifestPath  = appDir + "/manifest.json";
    QString signaturePath = appDir + "/SIGNATURE.txt";

    if (!QFile::exists(manifestPath)) {
        printError("manifest.json not found in: " + appDir);
        return 1;
    }

    printInfo("Signing manifest: " + manifestPath);
    if (!keyId.isEmpty()) {
        printInfo("Using GPG key: " + keyId);
    }

    MarathonAppVerifier verifier;

    if (verifier.signManifest(manifestPath, signaturePath, keyId)) {
        printSuccess("Manifest signed successfully");
        printInfo("Signature saved to: " + signaturePath);
        return 0;
    } else {
        printError("Failed to sign manifest: " + verifier.lastError());
        printInfo("Make sure you have GPG installed and a valid key configured");
        return 1;
    }
}

int validateCommand(const QStringList &args) {
    if (args.size() < 3) {
        printError("Usage: marathon-dev validate <app-directory|package-file>");
        return 1;
    }

    QString   path = args.at(2);
    QFileInfo pathInfo(path);

    printInfo("Validating: " + path);

    MarathonAppVerifier                     verifier;
    MarathonAppVerifier::VerificationResult result;

    if (pathInfo.isDir()) {
        // Validate directory
        result = verifier.verifyDirectory(path);
    } else if (path.endsWith(".marathon")) {
        // For packages, we need to extract first
        printError("Direct package validation not supported yet");
        printInfo("Extract the package first, then validate the directory");
        return 1;
    } else {
        printError("Unknown file type. Expected directory or .marathon package");
        return 1;
    }

    switch (result) {
        case MarathonAppVerifier::Valid:
            printSuccess("Validation passed");
            printInfo("App is ready for installation");
            return 0;

        case MarathonAppVerifier::SignatureFileMissing:
            printError("SIGNATURE.txt not found");
            printInfo("Sign the app using: marathon-dev sign " + path);
            return 1;

        case MarathonAppVerifier::InvalidSignature:
            printError("Invalid GPG signature");
            printInfo(verifier.lastError());
            return 1;

        case MarathonAppVerifier::ManifestMissing: printError("manifest.json not found"); return 1;

        default: printError("Verification failed: " + verifier.lastError()); return 1;
    }
}

int installCommand(const QStringList &args) {
    if (args.size() < 3) {
        printError("Usage: marathon-dev install <package-file|app-directory>");
        return 1;
    }

    QString   path = args.at(2);
    QFileInfo pathInfo(path);

    printInfo("Installing: " + path);

    // Create installer components
    MarathonAppRegistry  registry;
    MarathonAppScanner   scanner(&registry);
    MarathonAppInstaller installer(&registry, &scanner);

    bool                 success = false;

    if (pathInfo.isDir()) {
        // Install from directory
        success = installer.installFromDirectory(path);
    } else if (path.endsWith(".marathon")) {
        // Install from package
        success = installer.installFromPackage(path);
    } else {
        printError("Unknown file type. Expected directory or .marathon package");
        return 1;
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

    QString appName = args.at(2);
    QString appId   = appName.toLower().replace(" ", "-");

    // Create app directory
    QDir dir;
    if (!dir.mkdir(appId)) {
        printError("Failed to create directory: " + appId);
        return 1;
    }

    // Create subdirectories
    dir.cd(appId);
    dir.mkdir("pages");
    dir.mkdir("components");
    dir.mkdir("assets");

    // Create manifest.json
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

    // Create main QML file
    QString appFileName = appId.replace("-", "");
    appFileName[0]      = appFileName[0].toUpper();
    appFileName += "App.qml";

    QString qmlTemplate = QString(R"(import QtQuick
import QtQuick.Controls
import MarathonUI.Core
import MarathonUI.Controls
import MarathonOS.Shell

MApplicationWindow {
    id: root
    title: "%1"
    
    initialPage: mainPage
    
    Component {
        id: mainPage
        
        MPage {
            title: "%1"
            
            MColumn {
                anchors.centerIn: parent
                spacing: 20
                
                MText {
                    text: "Welcome to %1!"
                    type: MText.Heading
                }
                
                MButton {
                    text: "Get Started"
                    onClicked: {
                        console.log("Button clicked!")
                    }
                }
            }
        }
    }
}
)")
                              .arg(appName);

    QFile qmlFile(appId + "/" + appId.replace("-", "") + "App.qml");
    if (qmlFile.open(QIODevice::WriteOnly)) {
        qmlFile.write(qmlTemplate.toUtf8());
        qmlFile.close();
    }

    // Create qmldir
    QString qmldirContent = QString("module %1\n").arg(appId);
    QFile   qmldirFile(appId + "/qmldir");
    if (qmldirFile.open(QIODevice::WriteOnly)) {
        qmldirFile.write(qmldirContent.toUtf8());
        qmldirFile.close();
    }

    // Create placeholder icon
    QString iconSVG = R"(<?xml version="1.0" encoding="UTF-8"?>
<svg width="512" height="512" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
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
    printInfo("  4. Test with: marathon-dev validate .");
    printInfo("  5. Package with: marathon-dev package .");

    return 0;
}

void printHelp() {
    QTextStream out(stdout);
    out << "Marathon Developer Tool - Build and package Marathon apps\n\n";
    out << "Usage: marathon-dev <command> [options]\n\n";
    out << "Commands:\n";
    out << "  init <app-name>              Create a new app from template\n";
    out << "  package <app-dir> [output]   Package an app into .marathon file\n";
    out << "  sign <app-dir> [key-id]      Sign an app's manifest with GPG\n";
    out << "  validate <app-dir|package>   Validate an app or package\n";
    out << "  install <package|app-dir>    Install an app locally\n";
    out << "\n";
    out << "Examples:\n";
    out << "  marathon-dev init my-awesome-app\n";
    out << "  marathon-dev package ./my-app\n";
    out << "  marathon-dev sign ./my-app\n";
    out << "  marathon-dev validate ./my-app\n";
    out << "  marathon-dev install my-app.marathon\n";
    out << Qt::endl;
}

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationName("marathon-dev");
    QCoreApplication::setApplicationVersion("1.0.0");

    QStringList args = app.arguments();

    if (args.size() < 2) {
        printHelp();
        return 0;
    }

    QString command = args.at(1);

    if (command == "init") {
        return initCommand(args);
    } else if (command == "package") {
        return packageCommand(args);
    } else if (command == "sign") {
        return signCommand(args);
    } else if (command == "validate") {
        return validateCommand(args);
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
