# Keyboard Test Suite

cmake_minimum_required(VERSION 3.21)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core)

# The real keyboard QML and InputContext typing into a text field; registered
# in tests/CMakeLists.txt, which finds Keel's Silica for the keys.
find_package(Qt6 COMPONENTS QuickTest Quick QUIET)
if(Qt6QuickTest_FOUND)
    add_executable(test_keyboard_qml
        qml/main.cpp
        ../../shell/src/services/inputcontext.cpp
    )
    target_link_libraries(test_keyboard_qml Qt6::QuickTest Qt6::Quick marathon_shell_native)
    target_include_directories(test_keyboard_qml PRIVATE
        ${CMAKE_SOURCE_DIR}/shell
        ${CMAKE_SOURCE_DIR}/shell/src
    )
else()
    message(WARNING "Qt6QuickTest not found, skipping Keyboard QML tests")
endif()

# The real keyboard typing into a Qt app over text-input v2 through Qt's
# compositor, as on a device; registered in tests/CMakeLists.txt.
find_package(Qt6 COMPONENTS WaylandCompositor QUIET)
if(TARGET Qt6::WaylandCompositor)
    add_executable(test_keyboard_textinput
        cpp/test_keyboardtextinput.cpp
        ../../shell/src/services/inputcontext.cpp
    )
    target_link_libraries(test_keyboard_textinput
        Qt6::Test Qt6::Quick Qt6::WaylandCompositor marathon_shell_native)
    target_include_directories(test_keyboard_textinput PRIVATE
        ${CMAKE_SOURCE_DIR}/shell
        ${CMAKE_SOURCE_DIR}/shell/src
    )
    target_compile_definitions(test_keyboard_textinput PRIVATE
        MARATHON_KEYBOARD_QML="${CMAKE_SOURCE_DIR}/shell/qml/keyboard/Core/MarathonKeyboard.qml")
endif()
