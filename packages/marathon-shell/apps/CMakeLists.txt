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

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Qml
    Quick
)

# Optional WebEngine for browser
find_package(Qt6 6.5 COMPONENTS WebEngineQuick)
if(TARGET Qt6::WebEngineQuick)
    set(HAVE_WEBENGINE TRUE)
else()
    set(HAVE_WEBENGINE FALSE)
endif()

# Installation directory
set(MARATHON_APPS_DIR "$ENV{HOME}/.local/share/marathon-apps" CACHE PATH "Marathon apps installation directory")

# Function to create a Marathon app module
function(add_marathon_app APP_NAME)
    set(options HAS_CPP)
    set(oneValueArgs URI VERSION)
    set(multiValueArgs QML_FILES SOURCES RESOURCES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    
    # Set defaults
    if(NOT ARG_URI)
        set(ARG_URI "MarathonApp.${APP_NAME}")
    endif()
    
    if(NOT ARG_VERSION)
        set(ARG_VERSION "1.0")
    endif()
    
    set(APP_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    set(INSTALL_DIR "${MARATHON_APPS_DIR}/${APP_NAME}")
    
    
    # Create QML module
    if(ARG_HAS_CPP)
        # App with C++ plugin
        qt6_add_library(${APP_NAME}-plugin SHARED ${ARG_SOURCES})
        
        target_link_libraries(${APP_NAME}-plugin PRIVATE
            Qt6::Core
            Qt6::Qml
            Qt6::Quick
        )
        
        qt6_add_qml_module(${APP_NAME}-plugin
            URI ${ARG_URI}
            VERSION ${ARG_VERSION}
            QML_FILES ${ARG_QML_FILES}
            RESOURCES ${ARG_RESOURCES}
            OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/apps/${APP_NAME}"
            NO_PLUGIN_OPTIONAL
        )
        
        # Install plugin library
        install(TARGETS ${APP_NAME}-plugin
            LIBRARY DESTINATION "${INSTALL_DIR}"
            RUNTIME DESTINATION "${INSTALL_DIR}"
        )
        
        # Install QML module files
        install(DIRECTORY "${CMAKE_BINARY_DIR}/apps/${APP_NAME}/"
            DESTINATION "${INSTALL_DIR}"
            FILES_MATCHING PATTERN "*.qml" PATTERN "qmldir"
        )
    else()
        # Pure QML app - just copy files
        install(DIRECTORY "${APP_DIR}/"
            DESTINATION "${INSTALL_DIR}"
            FILES_MATCHING 
            PATTERN "*.qml"
            PATTERN "*.json"
            PATTERN "qmldir"
            PATTERN "*.svg"
            PATTERN "*.png"
            PATTERN "*.jpg"
        )
    endif()
    
    # Always install manifest and assets
    if(EXISTS "${APP_DIR}/manifest.json")
        install(FILES "${APP_DIR}/manifest.json" DESTINATION "${INSTALL_DIR}")
    endif()
    
    if(EXISTS "${APP_DIR}/qmldir")
        install(FILES "${APP_DIR}/qmldir" DESTINATION "${INSTALL_DIR}")
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

message(STATUS "==========================================")
message(STATUS "Marathon Apps Build Configuration")
message(STATUS "Installation directory: ${MARATHON_APPS_DIR}")
message(STATUS "WebEngine available: ${HAVE_WEBENGINE}")
message(STATUS "==========================================")

