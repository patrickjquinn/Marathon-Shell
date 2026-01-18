#include "screenshotservicecpp.h"

#include "audiopolicycontroller.h"
#include "hapticmanager.h"
#include "notificationservicecpp.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QQuickWindow>
#include <QStandardPaths>

ScreenshotServiceCpp::ScreenshotServiceCpp(AudioPolicyController  *audioPolicy,
                                           HapticManager          *haptics,
                                           NotificationServiceCpp *notificationService,
                                           QObject                *parent)
    : QObject(parent)
    , m_audioPolicy(audioPolicy)
    , m_haptics(haptics)
    , m_notificationService(notificationService) {
    m_screenshotsPath = resolveScreenshotsPath();
}

void ScreenshotServiceCpp::setShellWindow(QObject *window) {
    if (m_shellWindow == window)
        return;
    m_shellWindow = window;
    emit shellWindowChanged();
}

void ScreenshotServiceCpp::takeScreenshot(QObject *windowItem) {
    captureScreen(windowItem);
}

void ScreenshotServiceCpp::captureScreen(QObject *windowItem) {
    QObject *target = windowItem ? windowItem : m_shellWindow;
    if (!target) {
        notifyFailure("No window available");
        return;
    }

    const QString fullPath = buildScreenshotPath();

    if (auto *window = qobject_cast<QQuickWindow *>(target)) {
        const QImage image = window->grabWindow();
        if (image.isNull()) {
            notifyFailure("Failed to capture image");
            return;
        }
        if (!image.save(fullPath)) {
            notifyFailure("Failed to save file");
            return;
        }
        handleSavedScreenshot(fullPath);
        return;
    }

    auto *item = qobject_cast<QQuickItem *>(target);
    if (!item) {
        notifyFailure("grabToImage not supported");
        return;
    }

    QSharedPointer<QQuickItemGrabResult> grabResult = item->grabToImage();
    if (!grabResult) {
        notifyFailure("Failed to capture image");
        return;
    }

    QObject::connect(grabResult.data(), &QQuickItemGrabResult::ready, this,
                     [this, grabResult, fullPath]() {
                         if (!grabResult->saveToFile(fullPath)) {
                             notifyFailure("Failed to save file");
                             return;
                         }
                         handleSavedScreenshot(fullPath);
                     });
}

QString ScreenshotServiceCpp::resolveScreenshotsPath() const {
    const QString homePath     = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    const QString picturesPath = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    QString       path;
    if (!picturesPath.isEmpty())
        path = picturesPath + "/Screenshots/";
    else if (!homePath.isEmpty())
        path = homePath + "/Pictures/Screenshots/";
    else
        path = "/tmp/Screenshots/";

    QDir dir(path);
    dir.mkpath(".");
    return path;
}

QString ScreenshotServiceCpp::buildScreenshotPath() const {
    const QString timestamp = QDateTime::currentDateTime().toString("yyyy-MM-dd_HH-mm-ss");
    const QString filename  = "Screenshot_" + timestamp + ".png";
    return m_screenshotsPath + filename;
}

void ScreenshotServiceCpp::handleSavedScreenshot(const QString &filePath) {
    emit screenshotCaptured(filePath, filePath);

    if (m_audioPolicy)
        m_audioPolicy->playNotificationSound();
    if (m_haptics)
        m_haptics->medium();
    if (m_notificationService) {
        QVariantMap options;
        options["icon"]     = "camera";
        options["category"] = "system";
        options["priority"] = "low";
        m_notificationService->sendNotification("system", "Screenshot captured",
                                                QFileInfo(filePath).fileName(), options);
    }
}

void ScreenshotServiceCpp::notifyFailure(const QString &message) {
    emit screenshotFailed(message);
}
