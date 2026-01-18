# Calendar App - Events and scheduling

set(APP_NAME calendar)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    src/CalendarStorage.cpp
    src/CalendarStorage.h
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Calendar"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)
