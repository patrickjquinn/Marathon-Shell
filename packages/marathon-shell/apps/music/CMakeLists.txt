# Music App - Audio player

set(APP_NAME music)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    # Future: src/musicplayer.cpp
    # Future: src/playlistmanager.cpp
    # Future: src/metadatareader.cpp
)

if(SOURCES)
    add_marathon_app(${APP_NAME}
        HAS_CPP
        URI "MarathonApp.Music"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
        SOURCES ${SOURCES}
    )
    
    target_link_libraries(${APP_NAME}-plugin PRIVATE Qt6::Multimedia)
else()
    add_marathon_app(${APP_NAME}
        URI "MarathonApp.Music"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
    )
endif()

