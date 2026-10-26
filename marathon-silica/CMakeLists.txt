# Marathon.Silica: Keel's Silica plus accessibility, keyboard operation and
# the components Silica lacks. Plain QML, installed beside Sailfish.Silica.
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/Marathon
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/qt6/qml)

# The silica catalog; the shell and the app runner embed it.
set(_silica_dir ${CMAKE_SOURCE_DIR}/translations/silica)
file(GLOB_RECURSE _silica_qml CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/Marathon/*.qml)
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
