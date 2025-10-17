# Camera App - Photo and video capture

set(APP_NAME camera)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    # Future: src/cameraengine.cpp
    # Future: src/mediaprocessor.cpp
)

if(SOURCES)
    add_marathon_app(${APP_NAME}
        HAS_CPP
        URI "MarathonApp.Camera"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
        SOURCES ${SOURCES}
    )
    
    # Link Multimedia for camera/video
    target_link_libraries(${APP_NAME}-plugin PRIVATE Qt6::Multimedia)
else()
    add_marathon_app(${APP_NAME}
        URI "MarathonApp.Camera"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
    )
endif()

