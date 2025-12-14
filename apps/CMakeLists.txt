# Marathon Apps Build System
# Each app is built as a separate QML module with optional C++ plugins

cmake_minimum_required(VERSION 3.21)

project(MarathonApps VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Use Homebrew Qt 6.9.3 for compatibility
set(CMAKE_PREFIX_PATH "/opt/homebrew/opt/qt@6" ${CMAKE_PREFIX_PATH})

find_package(Qt6 6.4 REQUIRED COMPONENTS
    Core
    Qml
    Quick
)

# Optional WebEngine for browser
find_package(Qt6 6.4 COMPONENTS WebEngineQuick)
if(TARGET Qt6::WebEngineQuick)
    set(HAVE_WEBENGINE TRUE)
else()
    set(HAVE_WEBENGINE FALSE)
endif()

# Installation directory - defaults to user-local for better DX
# 
# Development (default):
#   Apps install to: ~/.local/share/marathon-apps
#   No sudo required, works out of the box
#
# System-wide production install:
#   Override with: -DMARATHON_APPS_DIR=/usr/share/marathon-apps
#   Or set: -DCMAKE_INSTALL_PREFIX=/usr
#
# This prevents permission errors for new developers using raw CMake commands
# while still supporting system-wide deployment for production environments.
#
if(NOT DEFINED MARATHON_APPS_DIR)
    set(MARATHON_APPS_DIR "$ENV{HOME}/.local/share/marathon-apps" CACHE PATH "Marathon apps installation directory")
endif()

# Include QML linting module
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../cmake/QMLLint.cmake")
    include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/QMLLint.cmake)
endif()

# Function to create a Marathon app module
function(add_marathon_app APP_NAME)
    set(options "")
    set(oneValueArgs URI VERSION)
    set(multiValueArgs QML_FILES SOURCES RESOURCES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    if(NOT ARG_URI)
        set(ARG_URI "MarathonApp.${APP_NAME}")
    endif()
    
    if(NOT ARG_VERSION)
        set(ARG_VERSION "1.0")
    endif()
    
    set(APP_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    set(INSTALL_DIR "${MARATHON_APPS_DIR}/${APP_NAME}")
    
    qt_policy(SET QTP0001 NEW)
    qt_policy(SET QTP0004 NEW)
    
    string(REPLACE "." "/" MODULE_PATH "${ARG_URI}")
    set(MODULE_OUTPUT_DIR "${CMAKE_BINARY_DIR}/apps/${APP_NAME}/${MODULE_PATH}")
    
    set(RELATIVE_QML_FILES "")
    foreach(QML_FILE ${ARG_QML_FILES})
        get_filename_component(ABS_FILE "${QML_FILE}" ABSOLUTE)
        file(RELATIVE_PATH REL_FILE "${CMAKE_CURRENT_SOURCE_DIR}" "${ABS_FILE}")
        list(APPEND RELATIVE_QML_FILES "${REL_FILE}")
    endforeach()
    
    if(ARG_SOURCES) # HAS_CPP equiv 
        qt6_add_library(${APP_NAME} SHARED ${ARG_SOURCES})
        
        target_include_directories(${APP_NAME} PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}
            ${CMAKE_CURRENT_SOURCE_DIR}/src
        )
    else()
        qt6_add_library(${APP_NAME} SHARED)
    endif()

    target_link_libraries(${APP_NAME} PRIVATE
        Qt6::Core
        Qt6::Qml
        Qt6::Quick
    )
    
    if(APPLE)
        set(RPATH_VALUE "@loader_path")
    else()
        set(RPATH_VALUE "$ORIGIN")
    endif()
    set_target_properties(${APP_NAME} PROPERTIES
        INSTALL_RPATH "${RPATH_VALUE}"
        BUILD_WITH_INSTALL_RPATH FALSE
        SKIP_BUILD_RPATH FALSE
    )

    qt6_add_qml_module(${APP_NAME}
        URI ${ARG_URI}
        VERSION ${ARG_VERSION}
        QML_FILES ${RELATIVE_QML_FILES}
        RESOURCES ${ARG_RESOURCES}
        OUTPUT_DIRECTORY "${MODULE_OUTPUT_DIR}"
        NO_PLUGIN_OPTIONAL
    )

    if(APPLE)
        install(CODE "
            execute_process(
                COMMAND install_name_tool 
                    -delete_rpath \"${CMAKE_BINARY_DIR}/${APP_NAME}\"
                    -add_rpath \"@loader_path/..\"
                    \"${INSTALL_DIR}/${MODULE_PATH}/lib${APP_NAME}plugin.dylib\"
                ERROR_QUIET
            )
        ")
    endif()
    
    install(DIRECTORY "${MODULE_OUTPUT_DIR}/"
        DESTINATION "${INSTALL_DIR}/${MODULE_PATH}"
        FILES_MATCHING 
        PATTERN "qmldir"
        PATTERN "*.so"
        PATTERN "*.dylib"
    )
    
    if(QMLLINT_AVAILABLE)
        add_qmllint_target(${APP_NAME} ${ARG_QML_FILES})
    endif()
    
    if(EXISTS "${APP_DIR}/manifest.json")
        install(FILES "${APP_DIR}/manifest.json" DESTINATION "${INSTALL_DIR}")
    endif()
    
    if(EXISTS "${APP_DIR}/assets")
        install(DIRECTORY "${APP_DIR}/assets" DESTINATION "${INSTALL_DIR}")
    endif()
endfunction()

# Add apps subdirectories
add_subdirectory(browser)
add_subdirectory(settings)
add_subdirectory(clock)
add_subdirectory(calculator)
add_subdirectory(phone)
add_subdirectory(messages)
add_subdirectory(notes)
add_subdirectory(calendar)
add_subdirectory(camera)
add_subdirectory(gallery)
add_subdirectory(music)
add_subdirectory(maps)
add_subdirectory(terminal)
add_subdirectory(test)
add_subdirectory(store)

message(STATUS "==========================================")
message(STATUS "Marathon Apps Build Configuration")
message(STATUS "Installation directory: ${MARATHON_APPS_DIR}")
message(STATUS "WebEngine available: ${HAVE_WEBENGINE}")
message(STATUS "==========================================")
