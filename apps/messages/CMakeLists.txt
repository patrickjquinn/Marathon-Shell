# Messages App - SMS/MMS messaging

set(APP_NAME messages)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    # Future: src/messagemanager.cpp
    # Future: src/conversationmanager.cpp
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Messages"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)
