# Marathon Mail OAuth — QMF credential plugin.
#
# Builds a Qt6 plugin shared library that messageserver5 (from qmf-
# messageserver apk) loads when an account's CredentialsPlugin=marathon-
# oauth. The plugin shells out to /usr/bin/marathon-mail-oauth for fresh
# access tokens via XOAUTH2.
#
# Build requirements:
#   • Qt6::Core, Qt6::Network
#   • QmfMessageServer (provides qmailcredentials.h, libQmfMessageServer.so)
#
# This subdir is OPT-IN — marathon-services/CMakeLists.txt only descends
# into it when MARATHON_BUILD_MAIL_CREDENTIALS=ON, which the duranium
# build sets once qmf-dev is part of the build sysroot. Fedora dev hosts
# without qmf-dev installed simply skip this target.

cmake_minimum_required(VERSION 3.21)

find_package(Qt6 6.4 REQUIRED COMPONENTS Core Network)

# QmfMessageServer config lives at /usr/lib/cmake/QmfMessageServer/ when
# qmf-dev is installed. We search using the standard cmake module
# discovery path.
find_package(QmfMessageServer QUIET)
if(NOT QmfMessageServer_FOUND)
    # Fall back to manual library + header discovery for Alpine where
    # the upstream CMake config file isn't always shipped in qmf-dev.
    find_library(QMF_MESSAGESERVER_LIB NAMES QmfMessageServer-qt6 QmfMessageServer)
    find_library(QMF_CLIENT_LIB        NAMES QmfClient-qt6 QmfClient)
    find_path(QMF_MESSAGESERVER_INCLUDE qmailcredentials.h
              PATH_SUFFIXES qt6/QmfMessageServer)
    if(NOT QMF_MESSAGESERVER_LIB OR NOT QMF_MESSAGESERVER_INCLUDE)
        message(FATAL_ERROR
            "QMF MessageServer not found. Install qmf-dev (Alpine) or "
            "QtMessagingFramework dev headers (other distros) and retry.")
    endif()
endif()

qt6_add_plugin(marathonoauth
    CLASS_NAME MarathonOAuthPlugin
    marathonoauth.cpp
    marathonoauth.h
)

target_link_libraries(marathonoauth PRIVATE
    Qt6::Core
    Qt6::Network
)

if(QmfMessageServer_FOUND)
    target_link_libraries(marathonoauth PRIVATE QmfMessageServer)
else()
    target_include_directories(marathonoauth PRIVATE
        ${QMF_MESSAGESERVER_INCLUDE}
        ${QMF_MESSAGESERVER_INCLUDE}/../QmfClient
    )
    target_link_libraries(marathonoauth PRIVATE
        ${QMF_MESSAGESERVER_LIB}
        ${QMF_CLIENT_LIB}
    )
endif()

# QMF looks under <Qt6 plugin path>/messagingframework/credentials/ —
# qt6_add_plugin's default output dir is the build tree's plugins/
# subdir, so we re-route via OUTPUT_NAME + the install rule below.
set_target_properties(marathonoauth PROPERTIES
    OUTPUT_NAME marathonoauth
    PREFIX "lib"
)

install(TARGETS marathonoauth
    LIBRARY DESTINATION lib/qt6/plugins/messagingframework/credentials
)
