cmake_minimum_required(VERSION 3.21)

project(MarathonUI VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS
    Core
    Qml
    Quick
)

if(COMMAND qt_policy)
    qt_policy(SET QTP0001 NEW)
    qt_policy(SET QTP0004 NEW)
endif()

# Installation directory - system-wide for production, user-local for dev
if(CMAKE_INSTALL_PREFIX STREQUAL "/usr" OR CMAKE_INSTALL_PREFIX STREQUAL "/usr/local")
    set(MARATHON_UI_DIR "${CMAKE_INSTALL_PREFIX}/lib/qt6/qml/MarathonUI" CACHE PATH "MarathonUI installation directory")
else()
    # Default to user-local for development
    set(MARATHON_UI_DIR "$ENV{HOME}/.local/share/marathon-ui" CACHE PATH "MarathonUI installation directory")
endif()

# Override if explicitly set via cmake
if(DEFINED ENV{MARATHON_UI_DIR})
    set(MARATHON_UI_DIR "$ENV{MARATHON_UI_DIR}" CACHE PATH "MarathonUI installation directory" FORCE)
endif()

# Include QML linting module (from parent directory) BEFORE subdirectories
# This allows subdirectories to use QMLLINT_AVAILABLE and add_qmllint_target
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../cmake/QMLLint.cmake")
    include(${CMAKE_CURRENT_SOURCE_DIR}/../cmake/QMLLint.cmake)
endif()

# Singleton files will be marked in individual module CMakeLists.txt files

# Build all MarathonUI modules (order matters for dependencies)
add_subdirectory(Theme)
add_subdirectory(Core)
add_subdirectory(Controls)
add_subdirectory(Lists)
add_subdirectory(Navigation)
add_subdirectory(Feedback)
add_subdirectory(Modals)
add_subdirectory(Effects)
add_subdirectory(Containers)  # Last - depends on Controls

set(MARATHON_QML_IMPORT_PATH
    "${CMAKE_BINARY_DIR}/qmllint"
    "${CMAKE_BINARY_DIR}"
    "${CMAKE_BINARY_DIR}/shell/qml"
)
set(MARATHON_UI_QML_TARGETS
    marathon-ui-theme
    marathon-ui-core
    marathon-ui-controls
    marathon-ui-lists
    marathon-ui-navigation
    marathon-ui-feedback
    marathon-ui-modals
    marathon-ui-effects
    marathon-ui-containers
)
foreach(target IN LISTS MARATHON_UI_QML_TARGETS)
    if(TARGET ${target})
        set_property(TARGET ${target} APPEND PROPERTY QT_QML_IMPORT_PATH "${MARATHON_QML_IMPORT_PATH}")
    endif()
endforeach()

find_program(QMLPLUGINDUMP_EXECUTABLE
    NAMES qmlplugindump-qt6 qmlplugindump
    PATHS /usr/lib64/qt6/bin /usr/bin /usr/local/bin
)
find_program(PYTHON_EXECUTABLE
    NAMES python3 python
    PATHS /usr/bin /usr/local/bin
)
if(QMLPLUGINDUMP_EXECUTABLE)
    set(QMLDUMP_ROOT "${CMAKE_BINARY_DIR}/qmldump")
    set(QMLDUMP_IMPORT_PATH "${QMLDUMP_ROOT}:/usr/lib64/qt6/qml")
    add_custom_target(marathon-ui-qmltypes
        COMMAND ${CMAKE_COMMAND} -E make_directory ${QMLDUMP_ROOT}/MarathonUI
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_BINARY_DIR}/MarathonUI ${QMLDUMP_ROOT}/MarathonUI
        COMMAND ${CMAKE_COMMAND} -E make_directory ${QMLDUMP_ROOT}/MarathonOS
        COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_BINARY_DIR}/shell/qml/MarathonOS/Shell ${QMLDUMP_ROOT}/MarathonOS/Shell
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonUI/Theme/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonUI/Theme/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonUI/Core/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonUI/Core/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonUI/Controls/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonUI/Controls/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonUI/Lists/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonUI/Lists/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonUI/Navigation/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonUI/Navigation/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonUI/Feedback/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonUI/Feedback/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonUI/Modals/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonUI/Modals/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonUI/Effects/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonUI/Effects/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonUI/Containers/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonUI/Containers/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${CMAKE_COMMAND} -DIN=${QMLDUMP_ROOT}/MarathonOS/Shell/qmldir -DOUT=${QMLDUMP_ROOT}/MarathonOS/Shell/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldir.cmake
        COMMAND ${PYTHON_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/build_qml_dependencies.py ${QMLDUMP_ROOT}/MarathonUI ${QMLDUMP_ROOT}/dependencies.json
        COMMAND ${CMAKE_COMMAND} -E env PATH=/usr/lib64/qt6/libexec:$ENV{PATH} QML2_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} QML_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} ${QMLPLUGINDUMP_EXECUTABLE} -noinstantiate -dependencies ${QMLDUMP_ROOT}/dependencies.json MarathonUI.Theme 2.0 ${QMLDUMP_ROOT} -output ${CMAKE_BINARY_DIR}/MarathonUI/Theme/marathon-ui-theme.qmltypes
        COMMAND ${CMAKE_COMMAND} -E env PATH=/usr/lib64/qt6/libexec:$ENV{PATH} QML2_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} QML_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} ${QMLPLUGINDUMP_EXECUTABLE} -noinstantiate -dependencies ${QMLDUMP_ROOT}/dependencies.json MarathonUI.Core 2.0 ${QMLDUMP_ROOT} -output ${CMAKE_BINARY_DIR}/MarathonUI/Core/marathon-ui-core.qmltypes
        COMMAND ${CMAKE_COMMAND} -E env PATH=/usr/lib64/qt6/libexec:$ENV{PATH} QML2_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} QML_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} ${QMLPLUGINDUMP_EXECUTABLE} -noinstantiate -dependencies ${QMLDUMP_ROOT}/dependencies.json MarathonUI.Controls 2.0 ${QMLDUMP_ROOT} -output ${CMAKE_BINARY_DIR}/MarathonUI/Controls/marathon-ui-controls.qmltypes
        COMMAND ${CMAKE_COMMAND} -E env PATH=/usr/lib64/qt6/libexec:$ENV{PATH} QML2_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} QML_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} ${QMLPLUGINDUMP_EXECUTABLE} -noinstantiate -dependencies ${QMLDUMP_ROOT}/dependencies.json MarathonUI.Lists 2.0 ${QMLDUMP_ROOT} -output ${CMAKE_BINARY_DIR}/MarathonUI/Lists/marathon-ui-lists.qmltypes
        COMMAND ${CMAKE_COMMAND} -E env PATH=/usr/lib64/qt6/libexec:$ENV{PATH} QML2_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} QML_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} ${QMLPLUGINDUMP_EXECUTABLE} -noinstantiate -dependencies ${QMLDUMP_ROOT}/dependencies.json MarathonUI.Navigation 2.0 ${QMLDUMP_ROOT} -output ${CMAKE_BINARY_DIR}/MarathonUI/Navigation/marathon-ui-navigation.qmltypes
        COMMAND ${CMAKE_COMMAND} -E env PATH=/usr/lib64/qt6/libexec:$ENV{PATH} QML2_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} QML_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} ${QMLPLUGINDUMP_EXECUTABLE} -noinstantiate -dependencies ${QMLDUMP_ROOT}/dependencies.json MarathonUI.Feedback 2.0 ${QMLDUMP_ROOT} -output ${CMAKE_BINARY_DIR}/MarathonUI/Feedback/marathon-ui-feedback.qmltypes
        COMMAND ${CMAKE_COMMAND} -E env PATH=/usr/lib64/qt6/libexec:$ENV{PATH} QML2_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} QML_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} ${QMLPLUGINDUMP_EXECUTABLE} -noinstantiate -dependencies ${QMLDUMP_ROOT}/dependencies.json MarathonUI.Modals 2.0 ${QMLDUMP_ROOT} -output ${CMAKE_BINARY_DIR}/MarathonUI/Modals/marathon-ui-modals.qmltypes
        COMMAND ${CMAKE_COMMAND} -E env PATH=/usr/lib64/qt6/libexec:$ENV{PATH} QML2_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} QML_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} ${QMLPLUGINDUMP_EXECUTABLE} -noinstantiate -dependencies ${QMLDUMP_ROOT}/dependencies.json MarathonUI.Effects 2.0 ${QMLDUMP_ROOT} -output ${CMAKE_BINARY_DIR}/MarathonUI/Effects/marathon-ui-effects.qmltypes
        COMMAND ${CMAKE_COMMAND} -E env PATH=/usr/lib64/qt6/libexec:$ENV{PATH} QML2_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} QML_IMPORT_PATH=${QMLDUMP_IMPORT_PATH} ${QMLPLUGINDUMP_EXECUTABLE} -noinstantiate -dependencies ${QMLDUMP_ROOT}/dependencies.json MarathonUI.Containers 2.0 ${QMLDUMP_ROOT} -output ${CMAKE_BINARY_DIR}/MarathonUI/Containers/marathon-ui-containers.qmltypes
        DEPENDS marathon-shell ${MARATHON_UI_QML_TARGETS}
    )
    foreach(target IN LISTS MARATHON_UI_QML_TARGETS)
        if(TARGET ${target}_qmllint)
            add_dependencies(${target}_qmllint marathon-ui-qmltypes)
        endif()
    endforeach()
endif()

set(QMLLINT_MODULE_ROOT "${CMAKE_BINARY_DIR}/qmllint")
add_custom_target(marathon-ui-qmllint-modules
    COMMAND ${CMAKE_COMMAND} -E make_directory ${QMLLINT_MODULE_ROOT}/MarathonUI
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_BINARY_DIR}/MarathonUI ${QMLLINT_MODULE_ROOT}/MarathonUI
    COMMAND ${CMAKE_COMMAND} -E make_directory ${QMLLINT_MODULE_ROOT}/MarathonOS
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_BINARY_DIR}/shell/qml/MarathonOS/Shell ${QMLLINT_MODULE_ROOT}/MarathonOS/Shell
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonUI/Theme/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonUI/Theme/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonUI/Core/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonUI/Core/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonUI/Controls/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonUI/Controls/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonUI/Lists/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonUI/Lists/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonUI/Navigation/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonUI/Navigation/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonUI/Feedback/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonUI/Feedback/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonUI/Modals/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonUI/Modals/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonUI/Effects/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonUI/Effects/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonUI/Containers/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonUI/Containers/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    COMMAND ${CMAKE_COMMAND} -DIN=${QMLLINT_MODULE_ROOT}/MarathonOS/Shell/qmldir -DOUT=${QMLLINT_MODULE_ROOT}/MarathonOS/Shell/qmldir -P ${CMAKE_SOURCE_DIR}/cmake/StripQmldirForLint.cmake
    DEPENDS marathon-shell ${MARATHON_UI_QML_TARGETS}
)

message(STATUS "==========================================")
message(STATUS "MarathonUI Build Configuration")
message(STATUS "Version: ${PROJECT_VERSION}")
message(STATUS "Installation directory: ${MARATHON_UI_DIR}")
message(STATUS "==========================================")

