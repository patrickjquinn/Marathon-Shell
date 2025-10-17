# Notes App - Note taking application

set(APP_NAME notes)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    # Future: src/notesmanager.cpp
    # Future: src/notessync.cpp
)

if(SOURCES)
    add_marathon_app(${APP_NAME}
        HAS_CPP
        URI "MarathonApp.Notes"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
        SOURCES ${SOURCES}
    )
else()
    add_marathon_app(${APP_NAME}
        URI "MarathonApp.Notes"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
    )
endif()

