# Settings App - System configuration interface

set(APP_NAME settings)

set(QML_FILES
    SettingsApp.qml
    components/BluetoothPairDialog.qml
    components/SettingsPageTemplate.qml
    components/WiFiPasswordDialog.qml
    pages/AboutPage.qml
    pages/AppManagerPage.qml
    pages/AppSortPage.qml
    pages/BatteryPage.qml
    pages/BluetoothPage.qml
    pages/CellularPage.qml
    pages/DefaultAppsPage.qml
    pages/DisplayPage.qml
    pages/HiddenAppsPage.qml
    pages/NotificationsPage.qml
    pages/QuickSettingsPage.qml
    pages/ScalePage.qml
    pages/ScreenTimeoutPage.qml
    pages/SecurityPage.qml
    pages/SettingsMainPage.qml
    pages/SoundPage.qml
    pages/SoundPickerPage.qml
    pages/StoragePage.qml
    pages/WallpaperPage.qml
    pages/WiFiPage.qml
)

set(SOURCES
    src/StorageInfo.cpp
    src/StorageInfo.h
)

# Pure QML app (Settings primarily uses shell C++ backends)
add_marathon_app(${APP_NAME}
    HAS_CPP
    URI "MarathonApp.Settings"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)
