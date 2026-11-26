# Marathon.Silica: Keel's Silica plus accessibility, keyboard operation and
# the components Silica lacks, installed beside Sailfish.Silica. Compiled
# ahead of time (qmlcachegen) into a plugin whose resources hold the QML;
# the generated qmldir prefers them. Tests and the apps' own compilation
# import the source directory, whose hand-written qmldir lists the same
# types.
set(_silica_dir ${CMAKE_SOURCE_DIR}/translations/silica)
file(GLOB_RECURSE _silica_qml CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/Marathon/*.qml)
file(GLOB _silica_js CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/Marathon/Silica/*.js)
foreach(_f IN LISTS _silica_qml _silica_js)
    get_filename_component(_name "${_f}" NAME)
    set_source_files_properties(${_f} PROPERTIES QT_RESOURCE_ALIAS "${_name}")
endforeach()
# Libraries imported by path; Velocity is also a module member.
set_source_files_properties(${_silica_js} PROPERTIES QT_QML_SKIP_QMLDIR_ENTRY TRUE)
set_source_files_properties(Marathon/Silica/Velocity.js PROPERTIES QT_QML_SKIP_QMLDIR_ENTRY FALSE)
set_source_files_properties(Marathon/Silica/DialogHeaderBackdrop.qml PROPERTIES QT_QML_INTERNAL_TYPE TRUE)
set(_silica_out ${CMAKE_CURRENT_BINARY_DIR}/qml/Marathon/Silica)
qt_add_qml_module(marathonsilicaplugin
    URI Marathon.Silica
    VERSION 1.0
    PLUGIN_TARGET marathonsilicaplugin
    OUTPUT_DIRECTORY ${_silica_out}
    RESOURCE_PREFIX /qt/qml
    DEPENDENCIES QtQuick Sailfish.Silica
    QML_FILES ${_silica_qml} ${_silica_js}
)
target_link_libraries(marathonsilicaplugin PRIVATE Qt6::Quick)
set_target_properties(marathonsilicaplugin PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
# Keel's QML on a development host; devices have keel-silica in Qt's path.
if(DEFINED ENV{KEEL_QML})
    set_property(TARGET marathonsilicaplugin PROPERTY QT_QML_IMPORT_PATH "$ENV{KEEL_QML}")
endif()
install(TARGETS marathonsilicaplugin
    LIBRARY DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/qt6/qml/Marathon/Silica)
install(DIRECTORY ${_silica_out}/
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/qt6/qml/Marathon/Silica
    FILES_MATCHING PATTERN "qmldir" PATTERN "*.qmltypes")

# The silica catalog; the shell and the app runner embed it.
list(TRANSFORM MARATHON_LANGUAGES REPLACE "^(.+)$" "${_silica_dir}/silica_\\1.ts" OUTPUT_VARIABLE _silica_ts)
qt_add_lupdate(SOURCES ${_silica_qml}
    TS_FILES ${_silica_ts}
    PLURALS_TS_FILE ${_silica_dir}/silica_en.ts
    LUPDATE_TARGET silica_lupdate
    OPTIONS -no-obsolete -locations relative
)
qt_add_lrelease(TS_FILES ${_silica_ts} ${_silica_dir}/silica_en.ts
    LRELEASE_TARGET silica_lrelease
    QM_FILES_OUTPUT_VARIABLE MARATHON_SILICA_QM
)
set(MARATHON_SILICA_QM ${MARATHON_SILICA_QM} PARENT_SCOPE)
