import QtQuick
import QtQuick.Window
import MarathonOS.Shell

QtObject {
    id: root
    
    property var shell: null
    
    function initialize(shellRef, rootWindow) {
        root.shell = shellRef
        
        WallpaperStore.currentWallpaper = SettingsManagerCpp.wallpaperPath
        
        Constants.updateScreenSize(shellRef.width, shellRef.height, Screen.pixelDensity * 25.4)
        UIStore.shellRef = shellRef
        Logger.info("ShellInitialization", "Screen size: " + shellRef.width + "x" + shellRef.height + " @ " + Math.round(Screen.pixelDensity * 25.4) + " DPI")
        Logger.info("ShellInitialization", "Scale factor: " + Constants.scaleFactor + " (base: " + (Constants.screenHeight / Constants.baseHeight) + " x user: " + Constants.userScaleFactor + ")")
        
        shellRef.forceActiveFocus()
        Logger.info("ShellInitialization", "Marathon Shell initialized")
        
        var compositor = root.initializeCompositor(rootWindow)
        
        if (typeof BluetoothManagerCpp !== 'undefined' && BluetoothManagerCpp.enabled) {
            root.startBluetoothReconnect(shellRef)
        }
        
        root.logSystemServices()
        
        return compositor
    }
    
    function initializeCompositor(rootWindow) {
        if (typeof WaylandCompositorManager === 'undefined') {
            Logger.info("ShellInitialization", "Wayland Compositor not available on this platform (expected on macOS)")
            return null
        }
        
        if (!rootWindow) {
            Logger.info("ShellInitialization", "No root window provided (Wayland not available)")
            return null
        }
        
        var compositor = WaylandCompositorManager.createCompositor(rootWindow)
        
        if (compositor) {
            Logger.info("ShellInitialization", "Wayland Compositor initialized: " + compositor.socketName)
        } else {
            Logger.info("ShellInitialization", "Wayland Compositor not available on this platform")
        }
        
        return compositor
    }
    
    function logSystemServices() {
        Logger.info("ShellInitialization", "System Services:")
        Logger.info("ShellInitialization", "  - NetworkManager: " + (typeof NetworkManagerCpp !== 'undefined' ? "✓" : "✗"))
        Logger.info("ShellInitialization", "  - PowerManager: " + (typeof PowerManagerService !== 'undefined' ? "✓" : "✗"))
        Logger.info("ShellInitialization", "  - AudioManager: " + (typeof AudioManagerCpp !== 'undefined' ? "✓" : "✗"))
        Logger.info("ShellInitialization", "  - BluetoothManager: " + (typeof BluetoothManagerCpp !== 'undefined' ? "✓" : "✗"))
        Logger.info("ShellInitialization", "  - ModemManager: " + (typeof ModemManagerCpp !== 'undefined' ? "✓" : "✗"))
        Logger.info("ShellInitialization", "  - MPRIS2Controller: " + (typeof MPRIS2Controller !== 'undefined' ? "✓" : "✗"))
    }
    
    function startBluetoothReconnect(shellRef) {
        if (shellRef && shellRef.bluetoothReconnectTimer) {
            shellRef.bluetoothReconnectTimer.start()
        }
    }
}

