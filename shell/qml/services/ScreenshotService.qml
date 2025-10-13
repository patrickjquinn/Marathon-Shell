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
    
    function captureScreen(windowItem) {
        console.log("[ScreenshotService] Capturing screenshot")
        
        if (!windowItem) {
            screenshotFailed("No window item provided")
            return
        }
        
        var timestamp = new Date().toISOString().replace(/:/g, "-")
        var filename = "Screenshot_" + timestamp + ".png"
        var fullPath = screenshotsPath + filename
        
        if (windowItem.grabToImage) {
            windowItem.grabToImage(function(result) {
                if (result) {
                    var saved = result.saveToFile(fullPath)
                    if (saved) {
                        console.log("[ScreenshotService] Screenshot saved:", fullPath)
                        screenshotCaptured(fullPath, result.image)
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
            screenshotFailed("grabToImage not supported")
        }
    }
    
    Component.onCompleted: {
        console.log("[ScreenshotService] Initialized")
        console.log("[ScreenshotService] Screenshots path:", screenshotsPath)
    }
}

