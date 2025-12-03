# Gallery App - Photo and video viewer

set(APP_NAME gallery)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    # Future: src/medialoader.cpp
    # Future: src/thumbnailgenerator.cpp
)

if(SOURCES)
    add_marathon_app(${APP_NAME}
        HAS_CPP
        URI "MarathonApp.Gallery"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
        SOURCES ${SOURCES}
    )
    
    target_link_libraries(${APP_NAME}-plugin PRIVATE Qt6::Multimedia)
else()
    add_marathon_app(${APP_NAME}
        URI "MarathonApp.Gallery"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
    )
endif()


# Updated QML files glob
