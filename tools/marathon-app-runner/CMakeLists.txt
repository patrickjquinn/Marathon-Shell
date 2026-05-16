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

# WebEngine init moved from shell to runner so the shell process
# doesn't map ~50 MB of WebEngine/chromium .so's. Apps that import
# QtWebEngine link it themselves (see apps/maps/CMakeLists.txt); the
# runner just needs the headers + symbol so it can call
# QtWebEngineQuick::initialize() before constructing QGuiApplication.
find_package(Qt6 6.4 COMPONENTS WebEngineQuick)

set(SOURCES
    main.cpp
    ipc/shellipcclients.cpp
    calendarmanagercpp.cpp
)

qt6_add_executable(marathon-app-runner ${SOURCES})

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

if(TARGET Qt6::WebEngineQuick)
    target_link_libraries(marathon-app-runner PRIVATE Qt6::WebEngineQuick)
    target_compile_definitions(marathon-app-runner PRIVATE HAVE_WEBENGINE)
endif()

install(TARGETS marathon-app-runner
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
