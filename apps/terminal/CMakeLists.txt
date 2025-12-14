set(APP_NAME terminal)


file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    src/TerminalEngine.cpp
    src/TerminalEngine.h
    src/TerminalScreen.cpp
    src/TerminalScreen.h
    src/TerminalRenderer.cpp
    src/TerminalRenderer.h
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Terminal"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)
