#ifndef SCREENSHOTSERVICECPP_H
#define SCREENSHOTSERVICECPP_H

#include <QObject>
#include <QString>

namespace marathon {
    class Audio;
}
class Haptics;
class Notifications;

class ScreenshotServiceCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString screenshotsPath READ screenshotsPath NOTIFY screenshotsPathChanged)
    Q_PROPERTY(QObject *shellWindow READ shellWindow WRITE setShellWindow NOTIFY shellWindowChanged)
    // Asked showsSecureContent() before every capture.
    Q_PROPERTY(QObject *compositor MEMBER m_compositor NOTIFY compositorChanged)

  public:
    explicit ScreenshotServiceCpp(marathon::Audio *audioPolicy, Haptics *haptics,
                                  Notifications *notificationService, QObject *parent = nullptr);

    QString screenshotsPath() const {
        return m_screenshotsPath;
    }

    QObject *shellWindow() const {
        return m_shellWindow;
    }
    void             setShellWindow(QObject *window);

    Q_INVOKABLE void takeScreenshot(QObject *windowItem = nullptr);
    Q_INVOKABLE void captureScreen(QObject *windowItem = nullptr);

    // Headless capture: grab the shell window and write straight to a
    // caller-supplied PNG path, bypassing the gallery folder + audio
    // shutter notifications. Used by the visual-validate harness.
    Q_INVOKABLE bool saveScreenshotTo(const QString &absolutePath);

  signals:
    void screenshotsPathChanged();
    void shellWindowChanged();
    void compositorChanged();
    void screenshotCaptured(const QString &filePath, const QString &thumbnailPath);
    void screenshotFailed(const QString &error);

  private:
    QString          resolveScreenshotsPath() const;
    QString          buildScreenshotPath() const;
    void             handleSavedScreenshot(const QString &filePath);
    void             notifyFailure(const QString &message);
    bool             secureContentShown() const;

    marathon::Audio *m_audioPolicy         = nullptr;
    Haptics         *m_haptics             = nullptr;
    Notifications   *m_notificationService = nullptr;
    QObject         *m_shellWindow         = nullptr;
    QObject         *m_compositor          = nullptr;
    QString          m_screenshotsPath;
};

#endif
