set(APP_NAME terminal)

set(QML_FILES
    TerminalApp.qml
    components/TerminalSession.qml
    components/TerminalTab.qml
    components/TerminalTabButton.qml
    components/VirtualKeyRow.qml
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
