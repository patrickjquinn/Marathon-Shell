# Gallery App - Photo and video viewer

set(APP_NAME gallery)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    # Future: src/medialoader.cpp
    # Future: src/thumbnailgenerator.cpp
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Gallery"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)
