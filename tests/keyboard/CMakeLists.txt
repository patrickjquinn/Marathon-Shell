# Keyboard Test Suite
# Organized tests for the Marathon keyboard component

cmake_minimum_required(VERSION 3.21)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core)
find_package(PkgConfig REQUIRED)
pkg_check_modules(HUNSPELL REQUIRED hunspell)

# C++ Unit Tests - WordTrie
add_executable(test_keyboard_wordtrie
    cpp/test_wordtrie.cpp
    ../../shell/qml/keyboard/Data/WordTrie.cpp
)
target_link_libraries(test_keyboard_wordtrie Qt6::Test Qt6::Core)
target_include_directories(test_keyboard_wordtrie PRIVATE ${CMAKE_SOURCE_DIR}/shell)
add_test(NAME Keyboard_WordTrie COMMAND test_keyboard_wordtrie)

# C++ Unit Tests - WordEngine
add_executable(test_keyboard_wordengine
    cpp/test_wordengine.cpp
    ../../shell/qml/keyboard/Data/WordEngine.cpp
    ../../shell/qml/keyboard/Data/WordTrie.cpp
)
target_link_libraries(test_keyboard_wordengine Qt6::Test Qt6::Core ${HUNSPELL_LIBRARIES})
target_include_directories(test_keyboard_wordengine PRIVATE 
    ${CMAKE_SOURCE_DIR}/shell 
    ${CMAKE_CURRENT_BINARY_DIR}/../../shell
    ${HUNSPELL_INCLUDE_DIRS}
)
target_compile_definitions(test_keyboard_wordengine PRIVATE HAVE_HUNSPELL)
add_test(NAME Keyboard_WordEngine COMMAND test_keyboard_wordengine)

# The real keyboard QML and InputContext typing into a text field; registered
# in tests/CMakeLists.txt, which finds Keel's Silica for the keys.
find_package(Qt6 COMPONENTS QuickTest Quick QUIET)
if(Qt6QuickTest_FOUND)
    add_executable(test_keyboard_qml
        qml/main.cpp
        ../../shell/src/services/inputcontext.cpp
        ../../shell/src/services/autocorrect.cpp
        ../../shell/src/services/dictionary.cpp
        ../../shell/src/services/domainsuggestions.cpp
        ../../shell/src/services/emojipredictor.cpp
        ../../shell/src/services/phrasepredictor.cpp
        ../../shell/qml/keyboard/Data/WordEngine.cpp
        ../../shell/qml/keyboard/Data/WordTrie.cpp
    )
    target_link_libraries(test_keyboard_qml Qt6::QuickTest Qt6::Quick ${HUNSPELL_LIBRARIES})
    target_include_directories(test_keyboard_qml PRIVATE
        ${CMAKE_SOURCE_DIR}/shell
        ${CMAKE_SOURCE_DIR}/shell/src
        ${HUNSPELL_INCLUDE_DIRS}
    )
    target_compile_definitions(test_keyboard_qml PRIVATE HAVE_HUNSPELL)
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
        ../../shell/src/services/autocorrect.cpp
        ../../shell/src/services/dictionary.cpp
        ../../shell/src/services/domainsuggestions.cpp
        ../../shell/src/services/emojipredictor.cpp
        ../../shell/src/services/phrasepredictor.cpp
        ../../shell/qml/keyboard/Data/WordEngine.cpp
        ../../shell/qml/keyboard/Data/WordTrie.cpp
    )
    target_link_libraries(test_keyboard_textinput
        Qt6::Test Qt6::Quick Qt6::WaylandCompositor ${HUNSPELL_LIBRARIES})
    target_include_directories(test_keyboard_textinput PRIVATE
        ${CMAKE_SOURCE_DIR}/shell
        ${CMAKE_SOURCE_DIR}/shell/src
        ${HUNSPELL_INCLUDE_DIRS}
    )
    target_compile_definitions(test_keyboard_textinput PRIVATE HAVE_HUNSPELL
        MARATHON_KEYBOARD_QML="${CMAKE_SOURCE_DIR}/shell/qml/keyboard/Core/MarathonKeyboard.qml")
endif()
