pragma Singleton
import QtQuick

QtObject {
    id: screenshotService
    
    signal screenshotCaptured(string filePath, var thumbnail)
    signal screenshotFailed(string error)
    
    property string screenshotsPath: {
        if (Platform.isMacOS) {
            return "~/Pictures/Screenshots/"
        } else if (Platform.isLinux) {
            return "~/Pictures/Screenshots/"
        }
        return "~/Screenshots/"
    }
    
    property var shellWindow: null
    
    function captureScreen(windowItem) {
        console.log("[ScreenshotService] Capturing screenshot")
        
        // Use provided windowItem, or fallback to stored shellWindow
        var targetWindow = windowItem || shellWindow
        
        if (!targetWindow) {
            console.error("[ScreenshotService] No window available for capture")
            screenshotFailed("No window available")
            return
        }
        
        var timestamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")
        var filename = "Screenshot_" + timestamp + ".png"
        var fullPath = screenshotsPath + filename
        
        // Ensure screenshots directory exists (FileService may not be available)
        // Directory will be created by system when saving
        
        if (targetWindow.grabToImage) {
            targetWindow.grabToImage(function(result) {
                if (result) {
                    var saved = result.saveToFile(fullPath)
                    if (saved) {
                        console.log("[ScreenshotService] Screenshot saved:", fullPath)
                        screenshotCaptured(fullPath, result.image)
                        
                        // Show notification
                        if (typeof NotificationService !== 'undefined') {
                            NotificationService.createNotification({
                                summary: "Screenshot captured",
                                body: filename,
                                urgency: "low",
                                timeout: 3000,
                                appName: "Marathon Shell",
                                icon: "camera"
                            })
                        }
                        
                        // Haptic feedback
                        if (typeof HapticService !== 'undefined') {
                            HapticService.light()
                        }
                    } else {
                        console.error("[ScreenshotService] Failed to save screenshot")
                        screenshotFailed("Failed to save file")
                    }
                } else {
                    console.error("[ScreenshotService] Failed to capture screenshot")
                    screenshotFailed("Failed to capture image")
                }
            })
        } else {
            console.error("[ScreenshotService] grabToImage not supported")
            screenshotFailed("grabToImage not supported")
        }
    }
    
    Component.onCompleted: {
        console.log("[ScreenshotService] Initialized")
        console.log("[ScreenshotService] Screenshots path:", screenshotsPath)
    }
}

