cmake_minimum_required(VERSION 3.21)

enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core)

add_executable(test_wordtrie
    test_wordtrie.cpp
    ../shell/qml/keyboard/Data/WordTrie.cpp
)

target_link_libraries(test_wordtrie
    Qt6::Test
    Qt6::Core
)

target_include_directories(test_wordtrie PRIVATE
    ${CMAKE_SOURCE_DIR}/shell
)

add_test(NAME WordTrieTest COMMAND test_wordtrie)

add_executable(test_wordtrie_integration
    test_wordtrie_integration.cpp
    ../shell/qml/keyboard/Data/WordTrie.cpp
)

target_link_libraries(test_wordtrie_integration
    Qt6::Test
    Qt6::Core
)

target_include_directories(test_wordtrie_integration PRIVATE
    ${CMAKE_SOURCE_DIR}/shell
)

add_test(NAME WordTrieIntegrationTest COMMAND test_wordtrie_integration)

