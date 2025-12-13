# Settings App - System configuration interface

set(APP_NAME settings)

set(QML_FILES
    SettingsApp.qml
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

install(DIRECTORY components DESTINATION "${MARATHON_APPS_DIR}/settings")
install(DIRECTORY pages DESTINATION "${MARATHON_APPS_DIR}/settings")
