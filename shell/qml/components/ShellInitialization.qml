import QtQuick
import QtQuick.Window
import MarathonOS.Shell 1.0

QtObject {
    id: root

    property var shell: null
    property var compositor: null

    function initialize(shellRef, rootWindow) {
        root.shell = shellRef;
        // Prefer ScreenMetricsCpp.dpi when available so MARATHON_FORCE_DPI
        // (used for QEMU validation) takes effect; fall back to Qt's
        // pixelDensity-derived DPI on real hardware.
        var deviceDpi = (typeof ScreenMetricsCpp !== 'undefined' && ScreenMetricsCpp && ScreenMetricsCpp.dpi > 0) ? ScreenMetricsCpp.dpi : Screen.pixelDensity * 25.4;
        Constants.updateScreenSize(shellRef.width, shellRef.height, deviceDpi);
        UIStore.shellRef = shellRef;
        Logger.info("ShellInitialization", "Screen size: " + shellRef.width + "x" + shellRef.height + " @ " + Math.round(deviceDpi) + " DPI");
        Logger.info("ShellInitialization", "Scale factor: " + Constants.scaleFactor + " (base: " + (Constants.screenHeight / Constants.baseHeight) + " x user: " + Constants.userScaleFactor + ")");
        shellRef.forceActiveFocus();
        Logger.info("ShellInitialization", "Marathon Shell initialized");
        root.compositor = root.initializeCompositor(rootWindow);
        if (BluetoothManagerCpp.enabled)
            root.startBluetoothReconnect(shellRef);

        root.logSystemServices();
        return root.compositor;
    }

    function initializeCompositor(rootWindow) {
        if (!rootWindow) {
            Logger.info("ShellInitialization", "No root window provided (Wayland not available)");
            return null;
        }
        var compositor = WaylandCompositorManager.createCompositor(rootWindow);
        if (compositor)
            Logger.info("ShellInitialization", "Wayland Compositor initialized: " + compositor.socketName);
        else
            Logger.info("ShellInitialization", "Wayland Compositor not available on this platform");
        return compositor;
    }

    function logSystemServices() {
        Logger.info("ShellInitialization", "System Services initialized: NetworkManager, PowerManager, AudioManager, BluetoothManager, ModemManager, MPRIS2Controller");
    }

    function startBluetoothReconnect(shellRef) {
        if (shellRef && shellRef.bluetoothReconnectTimer)
            shellRef.bluetoothReconnectTimer.start();
    }

    Component.onCompleted: {
        DisplayManagerCpp.screenStateChanged.connect(function (on) {
            if (root.compositor)
                root.compositor.setCompositorActive(on);
        });
        RotationManager.orientationChanged.connect(function () {
            var orientation = RotationManager.currentOrientation;
            if (root.compositor)
                Logger.info("ShellInitialization", "Setting output orientation to: " + orientation);

            if (root.compositor)
                root.compositor.setOutputOrientation(orientation);
        });
    }
}
