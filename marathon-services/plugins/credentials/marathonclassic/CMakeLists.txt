# Marathon Mail Classic — QMF credential plugin (PLAIN/LOGIN over IMAP/SMTP).
#
# Sibling of marathonoauth. Shells out to /usr/bin/marathon-mail-oauth
# classic-get for the stored username + password (Secret-Service-backed).
# Built only when MARATHON_BUILD_MAIL_CREDENTIALS=ON.

cmake_minimum_required(VERSION 3.21)

find_package(Qt6 6.4 REQUIRED COMPONENTS Core)

find_package(QmfMessageServer QUIET)
if(NOT QmfMessageServer_FOUND)
    find_library(QMF_MESSAGESERVER_LIB QmfMessageServer)
    find_library(QMF_CLIENT_LIB        QmfClient)
    find_path(QMF_MESSAGESERVER_INCLUDE qmailcredentials.h
              PATH_SUFFIXES qt6/QmfMessageServer)
    if(NOT QMF_MESSAGESERVER_LIB OR NOT QMF_MESSAGESERVER_INCLUDE)
        message(FATAL_ERROR
            "QMF MessageServer not found. Install qmf-dev (Alpine) or "
            "QtMessagingFramework dev headers (other distros) and retry.")
    endif()
endif()

qt6_add_plugin(marathonclassic
    CLASS_NAME MarathonClassicPlugin
    marathonclassic.cpp
    marathonclassic.h
)

target_link_libraries(marathonclassic PRIVATE
    Qt6::Core
)

if(QmfMessageServer_FOUND)
    target_link_libraries(marathonclassic PRIVATE QmfMessageServer)
else()
    target_include_directories(marathonclassic PRIVATE
        ${QMF_MESSAGESERVER_INCLUDE}
        ${QMF_MESSAGESERVER_INCLUDE}/../QmfClient
    )
    target_link_libraries(marathonclassic PRIVATE
        ${QMF_MESSAGESERVER_LIB}
        ${QMF_CLIENT_LIB}
    )
endif()

set_target_properties(marathonclassic PROPERTIES
    OUTPUT_NAME marathonclassic
    PREFIX "lib"
)

install(TARGETS marathonclassic
    LIBRARY DESTINATION lib/qt6/plugins/messagingframework/credentials
)
