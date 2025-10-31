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

# Fix RPATH for terminal plugin library
# The plugin (terminal-pluginplugin.so) needs to find the library (libterminal-plugin.so)
# which is installed in the same app directory
if(TARGET terminal-plugin)
    set_target_properties(terminal-plugin PROPERTIES
        INSTALL_RPATH "$ORIGIN;$ORIGIN/../.."
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH_USE_LINK_PATH TRUE
    )
endif()

