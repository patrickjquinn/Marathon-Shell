# Phone App - Dialer, Contacts, Call History

set(APP_NAME phone)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

# C++ sources for telephony (future)
set(SOURCES
    # Future: src/callmanager.cpp
    # Future: src/contactsmanager.cpp
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Phone"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)
