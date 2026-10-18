# Clock App - Alarms, Timer, Stopwatch, World Clock

set(APP_NAME clock)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

# Include SVG assets in the QML module's QRC so `Qt.resolvedUrl("../assets/...")` works
# even when the app is loaded from `qrc:/qt/qml/MarathonApp/Clock/...`.
file(GLOB_RECURSE ASSET_FILES RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/*"
)

# Pure QML for now
add_marathon_app(${APP_NAME}
    URI "MarathonApp.Clock"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    RESOURCES ${ASSET_FILES}
)

install_keel_actions(${APP_NAME} keel-actions.json)
