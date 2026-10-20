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
    Sql
)

set(SOURCES
    main.cpp
    ../../shell/src/services/touchresampler.cpp
    pagetouch.cpp
    keelhost.cpp
    ambienceclient.cpp
    platformtypes.cpp
    wallpaperclient.cpp
    ipc/shellipcclients.cpp
    ipc/dbusnormalize.cpp
    calendarmanagercpp.cpp
    worldclockhelper.h
    ../../marathon-services/src/musiclibrarymanager.cpp
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
    ${CMAKE_CURRENT_SOURCE_DIR}/../../marathon-services/src
)

target_link_libraries(marathon-app-runner PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::GuiPrivate
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::DBus
    Qt6::Sql
    MarathonCore
    marathon_app_native
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

# Marathon.Platform described for qmllint; only its qmltypes is ever built.
# The Rust clients' QObjects are described from their generated headers.
set(_app_native_headers)
foreach(_client alarms contacts display location modem network permissions power sensors settings telephony)
    list(APPEND _app_native_headers
        "${CMAKE_BINARY_DIR}/crates/cxxqt-export/crates/marathon-app-native/include/marathon-app-native/src/${_client}.cxxqt.h")
endforeach()
set_source_files_properties(${_app_native_headers} PROPERTIES GENERATED TRUE)
qt6_add_library(marathon-platform-types STATIC)
set_target_properties(marathon-platform-types PROPERTIES EXCLUDE_FROM_ALL TRUE)
qt6_add_qml_module(marathon-platform-types
    URI Marathon.Platform
    VERSION 1.0
    NO_PLUGIN
    SOURCES
        platformqmltypes.h
        ipc/shellipcclients.h
        calendarmanagercpp.h
        wallpaperclient.h
        worldclockhelper.h
        ../../marathon-core/src/marathonappregistry.h
        ${_app_native_headers}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qmllint-types/Marathon/Platform
)
target_include_directories(marathon-platform-types PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../../marathon-core/src
)
target_link_libraries(marathon-platform-types PRIVATE Qt6::Qml Qt6::DBus marathon_app_native)
add_dependencies(qmllint-types marathon-platform-types_qmltyperegistration)

# Native Keel apps (Sailfish apps rebuilt on Keel's sailfishapp) under a Keel host
qt6_add_executable(marathon-keel-host keelhostmain.cpp keelhost.cpp hostedapp.cpp hostlifecycle.cpp ambienceclient.cpp sailjail.cpp)
target_link_libraries(marathon-keel-host PRIVATE Qt6::Core Qt6::DBus)
install(TARGETS marathon-keel-host RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
