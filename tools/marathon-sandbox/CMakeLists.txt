cmake_minimum_required(VERSION 3.16)
project(marathon-sandbox LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_executable(marathon-sandbox main.c)

install(TARGETS marathon-sandbox RUNTIME DESTINATION bin)
