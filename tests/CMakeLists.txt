# Marathon Tests
# Logically grouped tests for the mono repo

cmake_minimum_required(VERSION 3.21)
enable_testing()

# Core library tests (registry, packager, permissions, installer, scanner, desktop parser)
add_subdirectory(core)

# Shell component tests (router, models)
add_subdirectory(shell)

# Keyboard component tests
add_subdirectory(keyboard)
