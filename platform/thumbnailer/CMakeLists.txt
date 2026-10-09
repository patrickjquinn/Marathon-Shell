# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Nemo.Thumbnailer 1.0: nemo-qml-plugin-thumbnailer (BSD-3-Clause, see
# ../PROVENANCE.md) built for Qt 6, its thumbnail cache library compiled into
# the QML plugin (no C++ library is installed). Images are scaled in process
# into the shared thumbnail cache; videos and PDFs go to the system's
# thumbnaild-video / thumbnaild-pdf helpers, as upstream.

set(_thumbnailer_dir Nemo/Thumbnailer)
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_THUMBNAILER_MLITE QUIET IMPORTED_TARGET mlite6)
endif()
if(KEEL_REQUIRE_MLITE AND NOT KEEL_THUMBNAILER_MLITE_FOUND)
    message(FATAL_ERROR "mlite6 not found (pkg-config mlite6, Chum's mlite-qt6-devel)")
endif()

add_library(nemothumbnailer MODULE
    plugin/plugin.cpp
    plugin/nemothumbnailitem.cpp plugin/nemothumbnailitem.h plugin/linkedlist.h
    plugin/nemothumbnailprovider.cpp plugin/nemothumbnailprovider.h
    lib/nemoimagemetadata.cpp lib/nemoimagemetadata.h
    lib/nemothumbnailcache.cpp lib/nemothumbnailcache.h lib/nemothumbnailexports.h)
set_target_properties(nemothumbnailer PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${_thumbnailer_dir}"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
# As upstream's lib.pro; the screen size comes from dconf through mlite
# (Chum's mlite-qt6) where it is found, else upstream's 540x960 default.
target_compile_definitions(nemothumbnailer PRIVATE BUILD_NEMO_QML_PLUGIN_THUMBNAILER_LIB)
target_include_directories(nemothumbnailer PRIVATE lib plugin)
# Upstream as it is (QCryptographicHash::addData(const char *, qsizetype)).
target_compile_options(nemothumbnailer PRIVATE -Wno-deprecated-declarations)
# Upstream includes QtGui/private/qimage_p.h (lib.pro: gui-private).
target_link_libraries(nemothumbnailer PRIVATE Qt6::Core Qt6::Gui Qt6::GuiPrivate Qt6::Qml Qt6::Quick)
if(KEEL_THUMBNAILER_MLITE_FOUND)
    target_compile_definitions(nemothumbnailer PRIVATE HAS_MLITE5)
    target_link_libraries(nemothumbnailer PRIVATE PkgConfig::KEEL_THUMBNAILER_MLITE)
endif()
foreach(_f qmldir plugins.qmltypes)
    configure_file(plugin/${_f} "${KEEL_QML_OUTPUT_DIR}/${_thumbnailer_dir}/${_f}" COPYONLY)
endforeach()
install(TARGETS nemothumbnailer LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${_thumbnailer_dir}")
install(FILES "${KEEL_QML_OUTPUT_DIR}/${_thumbnailer_dir}/qmldir" "${KEEL_QML_OUTPUT_DIR}/${_thumbnailer_dir}/plugins.qmltypes"
        DESTINATION "${KEEL_QML_INSTALL_DIR}/${_thumbnailer_dir}")
