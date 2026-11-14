# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# org.nemomobile.mpris 1.0: qtmpris (LGPL-2.1-or-later, see
# ../PROVENANCE.md) built for Qt 6, its MPRIS library and qtdbusextended
# compiled into the QML plugin. An MprisPlayer registers
# org.mpris.MediaPlayer2.<serviceName> on the session bus, where Lipstick's
# media controls (and any MPRIS client) find it.

set(_mpris_dir org/nemomobile/mpris)
add_library(mprisplugin MODULE
    declarative/mprisplugin.cpp declarative/mprisplugin.h
    src/mpris.cpp src/mpris.h src/mprisqt.h
    src/mprisrootadaptor.cpp src/mprisplayeradaptor.cpp
    src/mprisplayer.cpp src/mprisplayer.h src/mprisplayer_p.h
    src/mpriscontroller.cpp src/mpriscontroller.h src/mpriscontroller_p.h
    src/mprismanager.cpp src/mprismanager.h
    src/mprisplayerinterface.cpp src/mprisrootinterface.cpp
)
# qtdbusextended uses the emit keyword; built on its own without QT_NO_KEYWORDS.
add_library(keeldbusextended STATIC
    qtdbusextended/dbusextendedabstractinterface.cpp qtdbusextended/dbusextendedabstractinterface.h
    qtdbusextended/dbusextendedpendingcallwatcher.cpp qtdbusextended/dbusextendedpendingcallwatcher_p.h
    qtdbusextended/dbusextended.h)
set_target_properties(keeldbusextended PROPERTIES POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_include_directories(keeldbusextended PUBLIC qtdbusextended)
target_link_libraries(keeldbusextended PUBLIC Qt6::Core Qt6::DBus)
target_compile_options(keeldbusextended PRIVATE -Wno-deprecated-declarations)
set_target_properties(mprisplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${_mpris_dir}"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
# As upstream's src.pro (MPRIS_QT_LIBRARY, no_keywords).
target_compile_definitions(mprisplugin PRIVATE MPRIS_QT_LIBRARY QT_NO_KEYWORDS)
target_compile_options(mprisplugin PRIVATE -Wno-deprecated-declarations)
target_include_directories(mprisplugin PRIVATE src qtdbusextended declarative)
target_link_libraries(mprisplugin PRIVATE keeldbusextended Qt6::Core Qt6::DBus Qt6::Qml)
foreach(_f qmldir plugins.qmltypes)
    configure_file(declarative/${_f} "${KEEL_QML_OUTPUT_DIR}/${_mpris_dir}/${_f}" COPYONLY)
endforeach()
install(TARGETS mprisplugin LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${_mpris_dir}")
install(FILES "${KEEL_QML_OUTPUT_DIR}/${_mpris_dir}/qmldir" "${KEEL_QML_OUTPUT_DIR}/${_mpris_dir}/plugins.qmltypes"
        DESTINATION "${KEEL_QML_INSTALL_DIR}/${_mpris_dir}")
