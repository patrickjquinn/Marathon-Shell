cmake_minimum_required(VERSION 3.21)

project(MarathonServices LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS Core DBus Sql Gui Multimedia Network Xml Qml)

# QMF is shipped as `qmf-dev` on Alpine/Duranium. Dev hosts (Fedora etc.)
# don't have it; in that case we skip Mail-related build entirely and the
# Mail app surfaces its "service unavailable" state at runtime. The build
# never fails for lack of Mail support — auto-detect.
#
# Library naming: upstream QMF 4.0 ships the Qt6 build with a `-qt6` SONAME
# suffix (libQmfClient-qt6.so.6) to coexist with the legacy Qt5 build on
# distros that still package both. find_library tries both spellings; the
# qt6-suffixed name wins on Duranium/Alpine.
find_library(QMF_CLIENT_LIB        NAMES QmfClient-qt6 QmfClient)
find_library(QMF_MESSAGESERVER_LIB NAMES QmfMessageServer-qt6 QmfMessageServer)
find_path   (QMF_CLIENT_INCLUDE    qmailstore.h        PATH_SUFFIXES qt6/QmfClient)
find_path   (QMF_MS_INCLUDE        qmailcredentials.h  PATH_SUFFIXES qt6/QmfMessageServer)
if(QMF_CLIENT_LIB AND QMF_CLIENT_INCLUDE)
    set(MARATHON_HAS_QMF TRUE)
else()
    set(MARATHON_HAS_QMF FALSE)
    message(STATUS "MarathonServices: QMF not found — Mail backend will be skipped")
endif()

qt6_add_library(MarathonServices SHARED
    src/contactsmanager.h
    src/contactsmanager.cpp
    src/callhistorymanager.h
    src/callhistorymanager.cpp
    src/telephonyservice.h
    src/telephonyservice.cpp
    src/smsservice.h
    src/smsservice.cpp
    src/mmsmanager.h
    src/mmsmanager.cpp
    src/davsyncengine.h
    src/davsyncengine.cpp
    src/davcalendarstore.h
    src/davcalendarstore.cpp
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
        Qt6::Network
        Qt6::Xml
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

if(MARATHON_HAS_QMF)
    # MailService is a QML singleton exposed via the MarathonOS.Services
    # module. We register it through qt_add_qml_module so the import
    # `import MarathonOS.Services` resolves from the apps/email pages.
    qt6_add_qml_module(MarathonMailService
        URI MarathonOS.Services
        VERSION 1.0
        SOURCES
            src/mailservice.h
            src/mailservice.cpp
        OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonOS/Services
    )

    target_link_libraries(MarathonMailService PRIVATE
        Qt6::Core
        Qt6::DBus
        Qt6::Qml
        ${QMF_CLIENT_LIB}
    )
    if(QMF_MESSAGESERVER_LIB)
        target_link_libraries(MarathonMailService PRIVATE ${QMF_MESSAGESERVER_LIB})
    endif()
    target_include_directories(MarathonMailService PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${QMF_CLIENT_INCLUDE}
        ${QMF_MS_INCLUDE}
    )

    install(TARGETS MarathonMailService MarathonMailServiceplugin
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/MarathonOS/Services
        RUNTIME DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/MarathonOS/Services
    )
    install(FILES
        ${CMAKE_BINARY_DIR}/MarathonOS/Services/qmldir
        ${CMAKE_BINARY_DIR}/MarathonOS/Services/MarathonMailService.qmltypes
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/MarathonOS/Services
    )

    # Credential plugins (XOAUTH2 + classic-password) only build with the
    # full QMF dev tree because they pull qmailcredentials.h.
    if(QMF_MS_INCLUDE)
        add_subdirectory(plugins/credentials/marathonoauth)
        add_subdirectory(plugins/credentials/marathonclassic)
    endif()
endif()


