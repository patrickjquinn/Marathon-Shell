# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Amber.Mpris 1.0: amber-mpris (LGPL-2.1, see ../PROVENANCE.md) built for
# Qt 6, its MPRIS library and qtdbusextended compiled into the QML plugin (no
# C++ library is installed). An MprisPlayer registers
# org.mpris.MediaPlayer2.<serviceName> on the session bus; an
# MprisController follows the other players there.

set(_ambermpris_dir Amber/Mpris)
# Upstream's qtdbusextended.pro: a static library of its own (it uses the
# emit keyword, the MPRIS library is built with no_keywords).
add_library(keelamberdbusextended STATIC
    qtdbusextended/dbusextendedabstractinterface.cpp qtdbusextended/dbusextendedabstractinterface.h
    qtdbusextended/dbusextended.h)
set_target_properties(keelamberdbusextended PROPERTIES POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_compile_definitions(keelamberdbusextended PRIVATE QT_DBUS_EXTENDED_LIBRARY)
target_include_directories(keelamberdbusextended PUBLIC qtdbusextended)
target_link_libraries(keelamberdbusextended PUBLIC Qt6::Core Qt6::DBus)

add_library(ambermprisplugin MODULE
    declarative/mprisplugin.cpp declarative/mprisplugin.h
    declarative/declarativemprisplayer.cpp declarative/declarativemprisplayer_p.h
    src/mpris.cpp src/mpris.h src/mpris_p.h src/ambermpris.h src/ambermpris_p.h
    src/mprisclient.cpp src/mprisclient.h src/mprisclient_p.h
    src/mpriscontroller.cpp src/mpriscontroller.h
    src/mprisintrospectableadaptor.cpp src/mprisintrospectableadaptor_p.h
    src/mprismetadata.cpp src/mprismetadata.h src/mprismetadata_p.h
    src/mprismetadataproxy.cpp src/mprismetadataproxy.h
    src/mprisplayer.cpp src/mprisplayer.h src/mprisplayer_p.h
    src/mprisplayeradaptor.cpp src/mprisplayeradaptor_p.h
    src/mprisplayerinterface.cpp
    src/mprispropertiesadaptor.cpp src/mprispropertiesadaptor_p.h
    src/mprisrootinterface.cpp
    src/mprisserviceadaptor.cpp src/mprisserviceadaptor_p.h
)
set_target_properties(ambermprisplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${_ambermpris_dir}"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
# As upstream's src.pro (no_keywords; the export macro of ambermpris.h).
target_compile_definitions(ambermprisplugin PRIVATE AMBER_MPRIS_LIBRARY MPRIS_QT_LIBRARY QT_NO_KEYWORDS)
target_include_directories(ambermprisplugin PRIVATE src declarative)
target_link_libraries(ambermprisplugin PRIVATE keelamberdbusextended Qt6::Core Qt6::DBus Qt6::Qml)
foreach(_f qmldir plugins.qmltypes)
    configure_file(declarative/${_f} "${KEEL_QML_OUTPUT_DIR}/${_ambermpris_dir}/${_f}" COPYONLY)
endforeach()
install(TARGETS ambermprisplugin LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${_ambermpris_dir}")
install(FILES "${KEEL_QML_OUTPUT_DIR}/${_ambermpris_dir}/qmldir" "${KEEL_QML_OUTPUT_DIR}/${_ambermpris_dir}/plugins.qmltypes"
        DESTINATION "${KEEL_QML_INSTALL_DIR}/${_ambermpris_dir}")
