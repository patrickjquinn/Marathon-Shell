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

# QML Tests with Qt Quick Test
find_package(Qt6 COMPONENTS QuickTest QUIET)
if(Qt6QuickTest_FOUND)
    add_executable(test_keyboard_qml qml/main.cpp)
    target_link_libraries(test_keyboard_qml Qt6::QuickTest)
    add_test(NAME Keyboard_QML COMMAND test_keyboard_qml -input ${CMAKE_CURRENT_SOURCE_DIR}/qml)
    set_tests_properties(Keyboard_QML PROPERTIES
        ENVIRONMENT "QUICK_TEST_SOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/qml"
    )
else()
    message(WARNING "Qt6QuickTest not found, skipping Keyboard QML tests")
endif()
