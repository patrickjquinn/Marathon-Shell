# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Amber.Web.Authorization 1.0: amber-web-authorization (BSD-3-Clause, see
# ../PROVENANCE.md) built for Qt 6. The helper library is compiled into the
# QML plugin (no C++ library is installed).

find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS Network)

set(_amber_dir Amber/Web/Authorization)
add_library(amberwebauthorizationplugin MODULE
    import/plugin.cpp import/plugin.h
    lib/oauth1.cpp lib/oauth1.h lib/oauth2.cpp lib/oauth2.h
    lib/oautherror.cpp lib/oautherror.h lib/oauthsymbols.h
    lib/redirectlistener.cpp lib/redirectlistener.h
    lib/redirecturiparser.cpp lib/redirecturiparser_p.h)
set_target_properties(amberwebauthorizationplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${_amber_dir}"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_compile_definitions(amberwebauthorizationplugin PRIVATE AMBER_WEB_AUTHORIZATION_LIBRARY_BUILD)
target_include_directories(amberwebauthorizationplugin PRIVATE lib)
target_link_libraries(amberwebauthorizationplugin PRIVATE Qt6::Core Qt6::Network Qt6::Qml)
# Upstream as it is (QTranslator::load() results unchecked).
target_compile_options(amberwebauthorizationplugin PRIVATE -Wno-unused-result)
set(_amber_files qmldir plugins.qmltypes OAuth10a.qml OAuth2Ac.qml OAuth2AcPkce.qml OAuth2Implicit.qml httpcontent.js)
foreach(_f IN LISTS _amber_files)
    configure_file(import/${_f} "${KEEL_QML_OUTPUT_DIR}/${_amber_dir}/${_f}" COPYONLY)
    list(APPEND _amber_staged "${KEEL_QML_OUTPUT_DIR}/${_amber_dir}/${_f}")
endforeach()
install(TARGETS amberwebauthorizationplugin LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${_amber_dir}")
install(FILES ${_amber_staged} DESTINATION "${KEEL_QML_INSTALL_DIR}/${_amber_dir}")
