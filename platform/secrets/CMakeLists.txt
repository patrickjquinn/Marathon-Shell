# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# sailfish-secrets' client libraries and QML plugins (BSD-3-Clause, see
# ../PROVENANCE.md) built for Qt 6:
#   libsailfishsecrets-qt6.so.0  Sailfish::Secrets C++ API
#   libsailfishcrypto-qt6.so.0   Sailfish::Crypto C++ API
#   Sailfish.Secrets 1.0         QML plugin
#   Sailfish.Crypto 1.0          QML plugin
# They talk to the system's sailfishsecretsd (Qt 5) over its peer-to-peer
# D-Bus socket, as the Qt 5 libraries do; the wire format is not Qt's (D-Bus
# marshalling, and QDataStream at a fixed Qt_5_6 version for keys). The
# library names carry -qt6 so that they install next to Sailfish's Qt 5
# libsailfishsecrets.so.0 and libsailfishcrypto.so.0; headers go under
# include/sailfish-qt6/ for the same reason.

set(KEEL_SECRETS_VERSION 0.2.0)
set(KEEL_SECRETS_INCLUDEDIR "${CMAKE_INSTALL_INCLUDEDIR}/sailfish-qt6")

file(GLOB _secrets_lib_src CONFIGURE_DEPENDS lib/Secrets/*.cpp lib/Secrets/*.h)
file(GLOB _crypto_lib_src CONFIGURE_DEPENDS lib/Crypto/*.cpp lib/Crypto/*.h)

function(keel_secrets_library target define sources)
    add_library(${target} SHARED ${sources})
    set_target_properties(${target} PROPERTIES
        VERSION ${KEEL_SECRETS_VERSION} SOVERSION 0
        CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
    target_compile_definitions(${target} PRIVATE ${define})
    # Upstream as it is: QVariant::operator< and friends are deprecated in
    # Qt 6 (upstream's common.pri disables the warning too).
    target_compile_options(${target} PRIVATE -Wno-deprecated-declarations)
    target_include_directories(${target} PUBLIC
        "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/lib>"
        "$<INSTALL_INTERFACE:${KEEL_SECRETS_INCLUDEDIR}>")
    target_link_libraries(${target} PUBLIC Qt6::Core Qt6::DBus)
    install(TARGETS ${target} LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}")
endfunction()

keel_secrets_library(sailfishsecrets-qt6 SAILFISH_SECRETS_LIBRARY_BUILD "${_secrets_lib_src}")
keel_secrets_library(sailfishcrypto-qt6 SAILFISH_CRYPTO_LIBRARY_BUILD "${_crypto_lib_src}")

# Public and the "internal public" headers, as upstream installs them.
file(GLOB _secrets_headers lib/Secrets/*.h)
list(FILTER _secrets_headers EXCLUDE REGEX "_p\\.h$")
install(FILES ${_secrets_headers} lib/Secrets/secretsdaemonconnection_p.h lib/Secrets/serialization_p.h
        DESTINATION "${KEEL_SECRETS_INCLUDEDIR}/Secrets")
file(GLOB _crypto_headers lib/Crypto/*.h)
list(FILTER _crypto_headers EXCLUDE REGEX "_p\\.h$")
install(FILES ${_crypto_headers} lib/Crypto/cryptodaemonconnection_p.h lib/Crypto/serialization_p.h
        DESTINATION "${KEEL_SECRETS_INCLUDEDIR}/Crypto")
foreach(_lib sailfishsecrets sailfishcrypto)
    string(REPLACE "sailfish" "" _what "${_lib}")
    if(_what STREQUAL "secrets")
        set(_what_cap Secrets)
    else()
        set(_what_cap Crypto)
    endif()
    set(KEEL_PC_NAME "${_lib}-qt6")
    configure_file(sailfish-qt6.pc.in "${CMAKE_CURRENT_BINARY_DIR}/${_lib}-qt6.pc" @ONLY)
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${_lib}-qt6.pc" DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig")
endforeach()

# QML plugins: upstream's QQmlExtensionPlugins with upstream's qmltypes.
function(keel_secrets_qml target uri_dir library)
    set_target_properties(${target} PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${uri_dir}"
        CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
    target_compile_options(${target} PRIVATE -Wno-deprecated-declarations)
    target_link_libraries(${target} PRIVATE ${library} Qt6::Core Qt6::Qml)
    configure_file("qml/${uri_dir}.qmldir" "${KEEL_QML_OUTPUT_DIR}/${uri_dir}/qmldir" COPYONLY)
    string(REPLACE "Sailfish/" "" _sub "${uri_dir}")
    configure_file("qml/${_sub}/plugins.qmltypes" "${KEEL_QML_OUTPUT_DIR}/${uri_dir}/plugins.qmltypes" COPYONLY)
    install(TARGETS ${target} LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${uri_dir}")
    install(FILES "${KEEL_QML_OUTPUT_DIR}/${uri_dir}/qmldir" "${KEEL_QML_OUTPUT_DIR}/${uri_dir}/plugins.qmltypes"
            DESTINATION "${KEEL_QML_INSTALL_DIR}/${uri_dir}")
endfunction()

qt_add_library(sailfishsecretsplugin MODULE
    qml/Secrets/main.cpp qml/Secrets/plugintypes.h
    qml/Secrets/applicationinteractionview.cpp qml/Secrets/applicationinteractionview.h
    qml/Secrets/applicationinteractionview_p.h
    qml/Secrets/findsecretsrequestwrapper.cpp qml/Secrets/findsecretsrequestwrapper.h)
qt_add_resources(sailfishsecretsplugin secrets_qml PREFIX "/" BASE qml/Secrets
    FILES qml/Secrets/defaultInteractionView.qml)
target_link_libraries(sailfishsecretsplugin PRIVATE Qt6::Gui Qt6::Quick)
keel_secrets_qml(sailfishsecretsplugin Sailfish/Secrets sailfishsecrets-qt6)
configure_file(qml/Secrets/InteractionView.qml "${KEEL_QML_OUTPUT_DIR}/Sailfish/Secrets/InteractionView.qml" COPYONLY)
install(FILES qml/Secrets/InteractionView.qml DESTINATION "${KEEL_QML_INSTALL_DIR}/Sailfish/Secrets")

qt_add_library(sailfishcryptoplugin MODULE
    qml/Crypto/main.cpp qml/Crypto/plugintypes.h
    qml/Crypto/storedkeyidentifiersrequestwrapper.cpp qml/Crypto/storedkeyidentifiersrequestwrapper.h)
keel_secrets_qml(sailfishcryptoplugin Sailfish/Crypto sailfishcrypto-qt6)

