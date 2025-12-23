cmake_minimum_required(VERSION 3.21)

project(MarathonServices LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS Core DBus Sql Gui Multimedia)

qt6_add_library(MarathonServices SHARED
    src/contactsmanager.h
    src/contactsmanager.cpp
    src/callhistorymanager.h
    src/callhistorymanager.cpp
    src/telephonyservice.h
    src/telephonyservice.cpp
    src/smsservice.h
    src/smsservice.cpp
    src/medialibrarymanager.h
    src/medialibrarymanager.cpp
    src/musiclibrarymanager.h
    src/musiclibrarymanager.cpp
)

target_link_libraries(MarathonServices
    PUBLIC
        Qt6::Core
    PRIVATE
        Qt6::DBus
        Qt6::Sql
        Qt6::Gui
        Qt6::Multimedia
)

target_include_directories(MarathonServices
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src
)

install(TARGETS MarathonServices
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
)


