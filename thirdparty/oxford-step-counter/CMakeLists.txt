cmake_minimum_required(VERSION 3.0.0)
project(stepCountingAlgo LANGUAGES C VERSION 0.1.0)

#Debug flags (sanitizers)
set (CMAKE_C_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -fno-omit-frame-pointer -fsanitize=address -fsanitize=undefined") #-fsanitize=memory 
set (CMAKE_LINKER_FLAGS_DEBUG "${CMAKE_LINKER_FLAGS_DEBUG} -fno-omit-frame-pointer -fsanitize=address -fsanitize=undefined")

#Compile and link
include_directories(${PROJECT_SOURCE_DIR}/include)
set(SOURCES, "src/main.c")
file(GLOB SOURCES "src/*.c")
add_library(stepCountingAlgo ${SOURCES})
target_link_libraries(stepCountingAlgoTest m)

set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${PROJECT_VERSION})
include(CPack)
