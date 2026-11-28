#include "screenshotservicecpp.h"

#include "marathon-shell-native/src/audio.cxxqt.h"
#include "marathon-shell-native/src/haptics.cxxqt.h"
#include "marathon-shell-native/src/notifications.cxxqt.h"
#include "../components/nightlightitem.h"

#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QQuickItem>
#include <QQuickItemGrabResult>
#include <QQuickWindow>
#include <QPointer>
#include <QSGRendererInterface>
#include <QStandardPaths>
#include <QTimer>
#include <rhi/qrhi.h>

#include <atomic>
#include <memory>

namespace {

    // The shell's Window owns its items, so they are not the content item's
    // QObject children: walk the item tree.
    void collectNightLights(QQuickItem *item, QList<NightLightItem *> &out) {
        for (QQuickItem *child : item->childItems()) {
            if (auto *light = qobject_cast<NightLightItem *>(child))
                out.append(light);
            collectNightLights(child, out);
        }
    }

    QList<NightLightItem *> nightLights(QQuickWindow *window) {
        QList<NightLightItem *> lights;
        collectNightLights(window->contentItem(), lights);
        return lights;
    }

    // Night light warms the panel, not the picture: it is drawn into the
    // frame, so it leaves the frame for the grab.
    QImage grabUntinted(QQuickWindow *window) {
        const QList<NightLightItem *> lights = nightLights(window);
        for (NightLightItem *light : lights)
            light->setVisible(false);
        const QImage image = window->grabWindow();
        for (NightLightItem *light : lights)
            light->setVisible(true);
        return image;
    }

    struct ShownFrame {
        std::function<void(QImage)>     done;
        QList<QPointer<NightLightItem>> lights;
        QMetaObject::Connection         synced, rendered;
        std::atomic_bool                armed{false};
        bool                            finished = false;
        QRhiReadbackResult              readback;

        void                            finish(const QImage &image) {
            if (finished)
                return;
            finished = true;
            QObject::disconnect(synced);
            QObject::disconnect(rendered);
            for (const QPointer<NightLightItem> &light : std::as_const(lights))
                if (light)
                    light->setVisible(true);
            done(image);
        }
    };

    // Copies the frame the panel shows, read back from the swapchain right
    // after the scene graph draws it. grabWindow draws the scene a second
    // time, and that second pass leaves out the live frost's layers.
    void grabShownFrame(QQuickWindow *window, QObject *context, std::function<void(QImage)> done) {
        QRhi                 *rhi = window->rhi();
        QSGRendererInterface *ri  = window->rendererInterface();
        if (!rhi || !ri || !ri->getResource(window, QSGRendererInterface::RhiSwapchainResource)) {
            done(grabUntinted(window));
            return;
        }

        auto grab  = std::make_shared<ShownFrame>();
        grab->done = std::move(done);
        for (NightLightItem *light : nightLights(window)) {
            light->setVisible(false);
            grab->lights.append(light);
        }

        // A sync that starts after this point carries the hidden night light.
        grab->synced = QObject::connect(
            window, &QQuickWindow::beforeSynchronizing, window, [grab]() { grab->armed = true; },
            Qt::DirectConnection);
        grab->rendered = QObject::connect(
            window, &QQuickWindow::afterRendering, window,
            [grab, window, rhi, ri, context]() {
                if (!grab->armed.exchange(false))
                    return;
                QObject::disconnect(grab->synced);
                QObject::disconnect(grab->rendered);
                auto *swapChain = static_cast<QRhiSwapChain *>(
                    ri->getResource(window, QSGRendererInterface::RhiSwapchainResource));
                if (!swapChain)
                    return;
                grab->readback.completed = [grab, rhi, context]() {
                    const QRhiReadbackResult &r = grab->readback;
                    const QImage view(reinterpret_cast<const uchar *>(r.data.constData()),
                                      r.pixelSize.width(), r.pixelSize.height(),
                                      r.format == QRhiTexture::BGRA8 ? QImage::Format_RGB32 :
                                                                       QImage::Format_RGBX8888);
                    QImage       image = rhi->isYUpInFramebuffer() ? view.flipped() : view.copy();
                    QMetaObject::invokeMethod(
                        context, [grab, image]() { grab->finish(image); }, Qt::QueuedConnection);
                };
                QRhiResourceUpdateBatch *batch = rhi->nextResourceUpdateBatch();
                batch->readBackTexture(QRhiReadbackDescription(), &grab->readback);
                swapChain->currentFrameCommandBuffer()->resourceUpdate(batch);
            },
            Qt::DirectConnection);

        // A screen that is off draws no frame.
        QTimer::singleShot(1000, context, [grab]() { grab->finish(QImage()); });
        window->update();
    }

} // namespace

ScreenshotServiceCpp::ScreenshotServiceCpp(marathon::Audio *audioPolicy, Haptics *haptics,
                                           Notifications *notificationService, QObject *parent)
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
        notifyFailure(tr("No window available"));
        return;
    }

    if (secureContentShown()) {
        notifyFailure(tr("The app on screen doesn't allow screenshots"));
        return;
    }

    const QString fullPath = buildScreenshotPath();

    auto         *window = qobject_cast<QQuickWindow *>(target);
    if (auto *item = qobject_cast<QQuickItem *>(target);
        item && item->window() && item->size() == item->window()->size())
        window = item->window();
    if (window) {
        grabShownFrame(window, this, [this, fullPath](const QImage &image) {
            if (image.isNull()) {
                notifyFailure(tr("Failed to capture image"));
                return;
            }
            if (!image.save(fullPath)) {
                notifyFailure(tr("Failed to save file"));
                return;
            }
            handleSavedScreenshot(fullPath);
        });
        return;
    }

    auto *item = qobject_cast<QQuickItem *>(target);
    if (!item) {
        notifyFailure(tr("grabToImage not supported"));
        return;
    }

    QSharedPointer<QQuickItemGrabResult> grabResult = item->grabToImage();
    if (!grabResult) {
        notifyFailure(tr("Failed to capture image"));
        return;
    }

    QObject::connect(grabResult.data(), &QQuickItemGrabResult::ready, this,
                     [this, grabResult, fullPath]() {
                         if (!grabResult->saveToFile(fullPath)) {
                             notifyFailure(tr("Failed to save file"));
                             return;
                         }
                         handleSavedScreenshot(fullPath);
                     });
}

bool ScreenshotServiceCpp::saveScreenshotTo(const QString &absolutePath) {
    if (absolutePath.isEmpty() || !m_shellWindow || secureContentShown())
        return false;
    auto *window = qobject_cast<QQuickWindow *>(m_shellWindow);
    if (!window)
        return false;
    const QImage image = grabUntinted(window);
    if (image.isNull())
        return false;
    return image.save(absolutePath);
}

void ScreenshotServiceCpp::saveFrameTo(const QString            &absolutePath,
                                       std::function<void(bool)> done) {
    auto *window = qobject_cast<QQuickWindow *>(m_shellWindow);
    if (absolutePath.isEmpty() || !window || secureContentShown()) {
        done(false);
        return;
    }
    grabShownFrame(window, this, [absolutePath, done = std::move(done)](const QImage &image) {
        done(!image.isNull() && image.save(absolutePath));
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
        options["icon"]        = "camera";
        options["category"]    = "system";
        options["priority"]    = "low";
        options["route"]       = "/image";
        options["routeParams"] = QVariantMap{{"path", filePath}};
        m_notificationService->sendNotification("gallery", tr("Screenshot captured"),
                                                QFileInfo(filePath).fileName(), options);
    }
}

bool ScreenshotServiceCpp::secureContentShown() const {
    bool shown = false;
    if (m_compositor)
        QMetaObject::invokeMethod(m_compositor, "showsSecureContent", Qt::DirectConnection,
                                  qReturnArg(shown));
    return shown;
}

void ScreenshotServiceCpp::notifyFailure(const QString &message) {
    emit screenshotFailed(message);
}
