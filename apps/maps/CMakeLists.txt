# Maps App - Navigation and location services

set(APP_NAME maps)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/(tests|web)/")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Maps"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)

install_keel_actions(${APP_NAME} keel-actions.json)

# Link Positioning for GPS/location fallback (QtLocation Map is replaced
# by a WebEngineView + MapLibre GL JS render, but PositionSource is still
# the no-Geoclue fallback path).
find_package(Qt6 COMPONENTS Positioning)
if(TARGET Qt6::Positioning)
    target_link_libraries(${APP_NAME} PRIVATE Qt6::Positioning)
endif()

# WebEngine + WebChannel power the MapLibre GL JS basemap render and
# the JS↔QML bridge. Required (not optional) — Maps cannot render its
# basemap without them. Marathon-image must ship qt6-qtwebengine +
# qt6-qtwebchannel.
find_package(Qt6 REQUIRED COMPONENTS WebEngineQuick WebChannel WebChannelQuick)
target_link_libraries(${APP_NAME} PRIVATE
    Qt6::WebEngineQuick Qt6::WebChannel Qt6::WebChannelQuick)

install(DIRECTORY web
    DESTINATION "${MARATHON_APPS_DIR}/${APP_NAME}"
    FILES_MATCHING
        PATTERN "*.html"
        PATTERN "*.js"
        PATTERN "*.css"
        PATTERN "*.json"
        PATTERN "*.png"
        PATTERN "*.txt")
