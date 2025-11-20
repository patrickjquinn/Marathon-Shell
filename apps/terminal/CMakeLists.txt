set(APP_NAME terminal)

set(QML_FILES
    TerminalApp.qml
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
    HAS_CPP
    URI "MarathonApp.Terminal"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)

# TerminalEngine only needs Qt6::Core (for QProcess) - no additional dependencies!

install(DIRECTORY components DESTINATION "${MARATHON_APPS_DIR}/terminal")

