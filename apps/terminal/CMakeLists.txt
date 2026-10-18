set(APP_NAME terminal)


file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

set(SOURCES
    src/TerminalEngine.cpp
    src/TerminalEngine.h
    src/TerminalScreen.cpp
    src/TerminalScreen.h
    src/TerminalRenderer.cpp
    src/TerminalRenderer.h
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Terminal"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

install_keel_actions(${APP_NAME} keel-actions.json)
