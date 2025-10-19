set(APP_NAME terminal)

set(QML_FILES
    TerminalApp.qml
)

set(SOURCES
    src/TerminalEngine.cpp
    src/TerminalEngine.h
)

add_marathon_app(${APP_NAME}
    HAS_CPP
    URI "Terminal"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)

