# Music App - Audio player

set(APP_NAME music)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Music"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES src/MprisPlayer.cpp src/MprisPlayer.h src/Artwork.cpp src/Artwork.h
)

find_package(Qt6 REQUIRED COMPONENTS DBus Gui)
target_link_libraries(${APP_NAME} PRIVATE Qt6::DBus Qt6::Gui)

install_keel_actions(${APP_NAME} keel-actions.json)
