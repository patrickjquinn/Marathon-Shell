cmake_minimum_required(VERSION 3.16)

project(MarathonCore VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core)

# Core Marathon library for app management, packaging, and verification
set(SOURCES
    src/marathonapppackager.cpp
    src/marathonapppackager.h
    src/marathonappverifier.cpp
    src/marathonappverifier.h
    src/marathonappinstaller.cpp
    src/marathonappinstaller.h
    src/marathonappregistry.cpp
    src/marathonappregistry.h
    src/marathonappscanner.cpp
    src/marathonappscanner.h
)

add_library(MarathonCore SHARED ${SOURCES})

target_include_directories(MarathonCore PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(MarathonCore PUBLIC
    Qt6::Core
)

# Export for use by other targets
set_target_properties(MarathonCore PROPERTIES
    VERSION ${PROJECT_VERSION}
    SOVERSION 1
    PUBLIC_HEADER "src/marathonapppackager.h;src/marathonappverifier.h;src/marathonappinstaller.h;src/marathonappregistry.h;src/marathonappscanner.h"
)

install(TARGETS MarathonCore
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/marathon-core
)

