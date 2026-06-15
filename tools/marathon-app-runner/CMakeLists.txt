cmake_minimum_required(VERSION 3.16)

project(marathon-app-runner VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    DBus
)

set(SOURCES
    main.cpp
    ipc/shellipcclients.cpp
    calendarmanagercpp.cpp
)

qt6_add_executable(marathon-app-runner ${SOURCES})

# The installed shell qmldir keeps its native `prefer :/qt/qml/MarathonOS/Shell/`
# directive — when an app-runner-hosted app imports MarathonOS.Shell and
# touches Constants or Logger, Qt resolves the singleton path through that
# prefix into THIS binary's resource namespace. Mirror just the singleton
# QML files (and a synthetic sub-qmldir) at the exact rcc paths the prefer
# line points to so the lookup lands. See the .qrc for the historical
# context this replaces.
qt_add_resources(SHELL_SINGLETONS_RCC marathon-shell-singletons.qrc)
target_sources(marathon-app-runner PRIVATE ${SHELL_SINGLETONS_RCC})

target_include_directories(marathon-app-runner PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../marathon-core/src
    ${CMAKE_CURRENT_SOURCE_DIR}/../../shell/src
)

target_link_libraries(marathon-app-runner PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::DBus
    MarathonCore
)

# Qt WebEngine is the heaviest optional dependency in the OS. Linking it
# into a per-app process (instead of the shell) keeps the Chromium
# runtime cost scoped to apps that actually need it (Maps / Browser /
# Email), and lets it die with the app under the Phase B freezer / PSI
# kill path. Manifest must declare "requiresQtModules":["webengine"];
# main.cpp parses argv early, scans the manifest, and only calls
# QtWebEngineQuick::initialize() when required.
if(HAVE_WEBENGINE)
    target_link_libraries(marathon-app-runner PRIVATE Qt6::WebEngineQuick)
    target_compile_definitions(marathon-app-runner PRIVATE HAVE_WEBENGINE)
endif()

install(TARGETS marathon-app-runner
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
