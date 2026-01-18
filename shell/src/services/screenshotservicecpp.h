#ifndef SCREENSHOTSERVICECPP_H
#define SCREENSHOTSERVICECPP_H

#include <QObject>
#include <QString>

class AudioPolicyController;
class HapticManager;
class NotificationServiceCpp;

class ScreenshotServiceCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString screenshotsPath READ screenshotsPath NOTIFY screenshotsPathChanged)
    Q_PROPERTY(QObject *shellWindow READ shellWindow WRITE setShellWindow NOTIFY shellWindowChanged)

  public:
    explicit ScreenshotServiceCpp(AudioPolicyController *audioPolicy, HapticManager *haptics,
                                  NotificationServiceCpp *notificationService,
                                  QObject                *parent = nullptr);

    QString screenshotsPath() const {
        return m_screenshotsPath;
    }

    QObject *shellWindow() const {
        return m_shellWindow;
    }
    void             setShellWindow(QObject *window);

    Q_INVOKABLE void takeScreenshot(QObject *windowItem = nullptr);
    Q_INVOKABLE void captureScreen(QObject *windowItem = nullptr);

  signals:
    void screenshotsPathChanged();
    void shellWindowChanged();
    void screenshotCaptured(const QString &filePath, const QString &thumbnailPath);
    void screenshotFailed(const QString &error);

  private:
    QString                 resolveScreenshotsPath() const;
    QString                 buildScreenshotPath() const;
    void                    handleSavedScreenshot(const QString &filePath);
    void                    notifyFailure(const QString &message);

    AudioPolicyController  *m_audioPolicy         = nullptr;
    HapticManager          *m_haptics             = nullptr;
    NotificationServiceCpp *m_notificationService = nullptr;
    QObject                *m_shellWindow         = nullptr;
    QString                 m_screenshotsPath;
};

#endif
