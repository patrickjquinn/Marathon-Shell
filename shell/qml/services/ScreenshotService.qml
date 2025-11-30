pragma Singleton
import QtQuick
import QtCore

QtObject {
    id: screenshotService

    signal screenshotCaptured(string filePath, string thumbnailPath)
    signal screenshotFailed(string error)

    property string screenshotsPath: {
        // Use StandardPaths for proper path resolution
        var homePath = StandardPaths.writableLocation(StandardPaths.HomeLocation);
        var picturesPath = StandardPaths.writableLocation(StandardPaths.PicturesLocation);

        var path = "";
        if (picturesPath && picturesPath !== "") {
            path = picturesPath + "/Screenshots/";
        } else if (homePath && homePath !== "") {
            path = homePath + "/Pictures/Screenshots/";
        } else {
            path = "/tmp/Screenshots/";
        }

        // Remove file:// prefix if present
        if (path.indexOf("file://") === 0) {
            path = path.substring(7);
        }

        return path;
    }

    property var shellWindow: null

    // Alias for convenience
    function takeScreenshot(windowItem) {
        return captureScreen(windowItem);
    }

    function captureScreen(windowItem) {
        console.log("[ScreenshotService] Capturing screenshot");

        // Use provided windowItem, or fallback to stored shellWindow
        var targetWindow = windowItem || shellWindow;

        if (!targetWindow) {
            console.error("[ScreenshotService] No window available for capture");
            screenshotFailed("No window available");
            return;
        }

        var timestamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        var filename = "Screenshot_" + timestamp + ".png";
        var fullPath = screenshotsPath + filename;

        console.log("[ScreenshotService] Screenshots path:", screenshotsPath);
        console.log("[ScreenshotService] Full path:", fullPath);

        if (targetWindow.grabToImage) {
            targetWindow.grabToImage(function (result) {
                if (result) {
                    console.log("[ScreenshotService] Image grabbed, attempting to save...");
                    var saved = result.saveToFile(fullPath);
                    console.log("[ScreenshotService] Save result:", saved);
                    if (saved) {
                        console.log("[ScreenshotService] Screenshot saved:", fullPath);
                        // Emit with file path (not QImage) for preview
                        screenshotCaptured(fullPath, fullPath);

                        // Play camera shutter sound
                        if (typeof AudioManager !== 'undefined') {
                            AudioManager.playNotificationSound();
                        }

                        // Haptic feedback
                        if (typeof HapticService !== 'undefined') {
                            HapticService.medium();
                        }

                        // Show notification
                        if (typeof NotificationService !== 'undefined') {
                            NotificationService.sendNotification("system", "Screenshot captured", filename, {
                                icon: "camera",
                                category: "system",
                                priority: "low"
                            });
                        }
                    } else {
                        console.error("[ScreenshotService] Failed to save screenshot");
                        screenshotFailed("Failed to save file");
                    }
                } else {
                    console.error("[ScreenshotService] Failed to capture screenshot");
                    screenshotFailed("Failed to capture image");
                }
            });
        } else {
            console.error("[ScreenshotService] grabToImage not supported");
            screenshotFailed("grabToImage not supported");
        }
    }

    Component.onCompleted: {
        console.log("[ScreenshotService] Initialized");
        console.log("[ScreenshotService] Screenshots path:", screenshotsPath);
    }
}
