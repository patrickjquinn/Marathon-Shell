cmake_minimum_required(VERSION 3.21)

project(MarathonKeyboard VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

if(COMMAND qt_policy)
    qt_policy(SET QTP0001 NEW)
    qt_policy(SET QTP0004 NEW)
endif()

find_package(Qt6 6.4 REQUIRED COMPONENTS
    Core
    Qml
    Quick
    Gui
)

# Installation directory - system-wide for production
set(MARATHON_KEYBOARD_DIR "/usr/lib64/qt6/qml/MarathonKeyboard" CACHE PATH "MarathonKeyboard installation directory")

# C++ Backend Library - Input Method Engine
set(KEYBOARD_SOURCES
    src/marathoninputmethodengine.h
    src/marathoninputmethodengine.cpp
    src/marathonkeyboardime.h
    src/marathonkeyboardime.cpp
)

add_library(marathonkeyboard STATIC ${KEYBOARD_SOURCES})

target_link_libraries(marathonkeyboard
    PUBLIC
        Qt6::Core
        Qt6::Qml
        Qt6::Quick
        Qt6::Gui
)

target_include_directories(marathonkeyboard
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

# Core QML Module
set(CORE_QML_FILES
    qml/Core/MarathonKeyboard.qml
)

qt6_add_qml_module(marathon-keyboard-core
    URI MarathonKeyboard.Core
    VERSION 1.0
    QML_FILES ${CORE_QML_FILES}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonKeyboard/Core
)

# UI QML Module
set(UI_QML_FILES
    qml/UI/Key.qml
)

qt6_add_qml_module(marathon-keyboard-ui
    URI MarathonKeyboard.UI
    VERSION 1.0
    QML_FILES ${UI_QML_FILES}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonKeyboard/UI
)

# Layouts QML Module
set(LAYOUTS_QML_FILES
    qml/Layouts/SymbolLayout.qml
)

qt6_add_qml_module(marathon-keyboard-layouts
    URI MarathonKeyboard.Layouts
    VERSION 1.0
    QML_FILES ${LAYOUTS_QML_FILES}
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonKeyboard/Layouts
)

# Install all QML modules
install(TARGETS marathon-keyboard-core
    LIBRARY DESTINATION ${MARATHON_KEYBOARD_DIR}
    RUNTIME DESTINATION ${MARATHON_KEYBOARD_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonKeyboard/Core/
    DESTINATION ${MARATHON_KEYBOARD_DIR}/Core
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

install(TARGETS marathon-keyboard-ui
    LIBRARY DESTINATION ${MARATHON_KEYBOARD_DIR}
    RUNTIME DESTINATION ${MARATHON_KEYBOARD_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonKeyboard/UI/
    DESTINATION ${MARATHON_KEYBOARD_DIR}/UI
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

install(TARGETS marathon-keyboard-layouts
    LIBRARY DESTINATION ${MARATHON_KEYBOARD_DIR}
    RUNTIME DESTINATION ${MARATHON_KEYBOARD_DIR}
)

install(DIRECTORY ${CMAKE_BINARY_DIR}/MarathonKeyboard/Layouts/
    DESTINATION ${MARATHON_KEYBOARD_DIR}/Layouts
    FILES_MATCHING
    PATTERN "*.qml"
    PATTERN "qmldir"
    PATTERN "*.so"
    PATTERN "*.dylib"
    PATTERN "*.qmltypes"
)

# Install C++ library
install(TARGETS marathonkeyboard
    LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
    ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
)

# Install headers for apps that need direct C++ access
install(FILES
    src/marathoninputmethodengine.h
    src/marathonkeyboardime.h
    DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/marathon-keyboard"
)

message(STATUS "==========================================")
message(STATUS "MarathonKeyboard Build Configuration")
message(STATUS "Version: ${PROJECT_VERSION}")
message(STATUS "Installation directory: ${MARATHON_KEYBOARD_DIR}")
message(STATUS "==========================================")
