# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Keel's Sailfish platform modules beyond Silica and the Nemo plugins
# (PROVENANCE.md says where each comes from). So far:
#   Sailfish.Media 1.0     MediaKey (GRABBED_KEYS + app-wide key filter),
#                          MediaPlayerControls, MetadataReader, MediaListItem,
#                          MediaPlayerControlsPanel, MediaPlayerPanelBackground,
#                          MprisPlayerControls (over Amber.Mpris)
#   Sailfish.Pickers 1.0   picker pages and dialogs on Silica, over Tracker 3
#                          or a scan of the user's directories
#   Sailfish.WebView 1.0   WebView, WebViewPage, WebViewFlickable on Qt
#   Sailfish.WebEngine 1.0 WebEngine (Chum qt6-qtwebengine) when installed
#   Sailfish.Secrets 1.0,  sailfish-secrets' client libraries and QML plugins
#   Sailfish.Crypto 1.0    (BSD) built for Qt 6, talking to sailfishsecretsd
#   Amber.Web.Authorization 1.0  amber-web-authorization (BSD) for Qt 6:
#                          OAuth helpers and the redirect listener
#   org.nemomobile.mpris 1.0     qtmpris (LGPL) for Qt 6: MPRIS players on
#                          the session bus
#   Amber.Mpris 1.0        amber-mpris (LGPL) for Qt 6: MPRIS players and
#                          controllers on the session bus
#   Nemo.Thumbnailer 1.0   nemo-qml-plugin-thumbnailer (BSD) for Qt 6:
#                          Thumbnail and image://nemoThumbnail
#   Nemo.Mce 1.0           libmce-qt (BSD) for Qt 6: MCE state as QML types
#   org.nemomobile.accounts 1.0  nemo-qml-plugin-accounts (BSD) on
#                          libaccounts-qt 1.17 (LGPL) for Qt 6, where
#                          libaccounts-glib is found
#   Sailfish.Accounts 1.0  sailfish-components-accounts (BSD) for Qt 6 on
#                          the same, with libsignon-qt and libbuteosyncfw
#                          (LGPL) compiled in
#   Sailfish.Policy 1.0    PolicyValue and AccessPolicy (and
#                          libsailfishpolicy-qt6), reading MDM policies
#
# Each module is staged under ${KEEL_QML_OUTPUT_DIR} like the others and
# installed into Qt6's QML import path.

find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Qml Quick DBus)

# Installs a staged QML module directory (plugin, qmldir, qmltypes).
function(keel_platform_install target dir)
    install(TARGETS ${target} LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${dir}")
    install(DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${dir}/"
            DESTINATION "${KEEL_QML_INSTALL_DIR}/${dir}"
            FILES_MATCHING PATTERN "qmldir" PATTERN "*.qmltypes")
endfunction()

# Shared helpers (title tags), compiled into the plugins that use them.
add_library(keelplatformcommon STATIC common/tagreader.cpp common/tagreader.h)
set_target_properties(keelplatformcommon PROPERTIES POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_include_directories(keelplatformcommon PUBLIC common)
target_link_libraries(keelplatformcommon PUBLIC Qt6::Core)

# ---------------------------------------------------------------------------
# Sailfish.Media 1.0
# ---------------------------------------------------------------------------
foreach(_f MediaListItem.qml MediaPlayerControlsPanel.qml MediaPlayerPanelBackground.qml
        MprisPlayerControls.qml KeelMprisControls.qml)
    set_source_files_properties(media/${_f} PROPERTIES QT_RESOURCE_ALIAS ${_f})
endforeach()
# MprisPlayerControls loads its item (which imports Amber.Mpris) at run time,
# so the module works without Amber.Mpris; the item is not a public type.
set_source_files_properties(media/KeelMprisControls.qml PROPERTIES QT_QML_INTERNAL_TYPE TRUE)
qt_add_qml_module(sailfishmediaplugin
    URI Sailfish.Media
    RESOURCE_PREFIX /
    VERSION 1.0
    PLUGIN_TARGET sailfishmediaplugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/Media"
    DEPENDENCIES QtQuick Sailfish.Silica
    QML_FILES media/MediaListItem.qml media/MediaPlayerControlsPanel.qml media/MediaPlayerPanelBackground.qml
        media/MprisPlayerControls.qml
    RESOURCES media/KeelMprisControls.qml
    SOURCES
        media/mediakey.cpp media/mediakey.h
        media/mediatypes.cpp media/mediatypes.h
)
target_include_directories(sailfishmediaplugin PRIVATE media)
# QPlatformNativeInterface::setWindowProperty() for GRABBED_KEYS.
target_link_libraries(sailfishmediaplugin PRIVATE Qt6::Core Qt6::Gui Qt6::GuiPrivate Qt6::Qml keelplatformcommon)
keel_platform_install(sailfishmediaplugin Sailfish/Media)

# ---------------------------------------------------------------------------
# Sailfish.Pickers 1.0
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_PICKERS "Build Sailfish.Pickers (keel/platform/pickers)" ON)
set(_pickers_public
    ContentPickerPage DocumentPickerPage DownloadPickerPage FilePickerPage
    FolderPickerDialog FolderPickerPage ImagePickerPage MusicPickerPage VideoPickerPage
    MultiContentPickerDialog MultiDocumentPickerDialog MultiDownloadPickerDialog
    MultiFilePickerDialog MultiImagePickerDialog MultiMusicPickerDialog MultiVideoPickerDialog)
set(_pickers_internal
    PickerPageBase PickerSelection ContentDelegate ThumbnailDelegate ContentPickerView
    ContentPickerPageBase FileBrowserPage FolderBrowserPage MultiContentPickerDialogBase)
set(_pickers_qml)
foreach(_t IN LISTS _pickers_public _pickers_internal)
    set_source_files_properties(pickers/qml/${_t}.qml PROPERTIES QT_RESOURCE_ALIAS ${_t}.qml)
    list(APPEND _pickers_qml pickers/qml/${_t}.qml)
endforeach()
# Keel internals: `internal` qmldir entries (Qt 6.4 also lists them with a
# version; Qt 6.8 keeps them internal).
foreach(_t IN LISTS _pickers_internal)
    set_source_files_properties(pickers/qml/${_t}.qml PROPERTIES QT_QML_INTERNAL_TYPE TRUE)
endforeach()
if(KEEL_PLATFORM_PICKERS)
    qt_add_qml_module(sailfishpickersplugin
        URI Sailfish.Pickers
        RESOURCE_PREFIX /
        VERSION 1.0
        PLUGIN_TARGET sailfishpickersplugin
        OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/Pickers"
        DEPENDENCIES QtQuick Sailfish.Silica
        QML_FILES ${_pickers_qml}
        SOURCES
            pickers/contentitem.cpp pickers/contentitem.h
            pickers/filesource.cpp pickers/filesource.h
            pickers/trackersource.cpp pickers/trackersource.h
            pickers/pickermodels.cpp pickers/pickermodels.h
    )
    target_include_directories(sailfishpickersplugin PRIVATE pickers)
    target_link_libraries(sailfishpickersplugin PRIVATE Qt6::Core Qt6::DBus Qt6::Qml keelplatformcommon)
    keel_platform_install(sailfishpickersplugin Sailfish/Pickers)
endif()

# ---------------------------------------------------------------------------
# Sailfish.Gallery 1.0 (the types apps use: ThumbnailImage, ImageViewer)
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_GALLERY "Build Sailfish.Gallery (keel/platform/gallery)" ON)
if(KEEL_PLATFORM_GALLERY)
    foreach(_f ThumbnailImage.qml ImageViewer.qml)
        set_source_files_properties(gallery/${_f} PROPERTIES QT_RESOURCE_ALIAS ${_f})
    endforeach()
    qt_add_qml_module(sailfishgalleryplugin
        URI Sailfish.Gallery
        RESOURCE_PREFIX /
        VERSION 1.0
        PLUGIN_TARGET sailfishgalleryplugin
        OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/Gallery"
        DEPENDENCIES QtQuick Sailfish.Silica
        QML_FILES gallery/ThumbnailImage.qml gallery/ImageViewer.qml
    )
    keel_platform_install(sailfishgalleryplugin Sailfish/Gallery)
endif()

# ---------------------------------------------------------------------------
# Sailfish.WebEngine 1.0 and Sailfish.WebView 1.0
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_WEBVIEW "Build Sailfish.WebView and Sailfish.WebEngine (keel/platform/webview)" ON)
if(KEEL_PLATFORM_WEBVIEW)
    qt_add_qml_module(sailfishwebengineplugin
        URI Sailfish.WebEngine
        RESOURCE_PREFIX /
        VERSION 1.0
        PLUGIN_TARGET sailfishwebengineplugin
        OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/WebEngine"
        SOURCES webengine/webengine.cpp webengine/webengine.h
            webengine/permissionstore.cpp webengine/permissionstore.h
            webengine/upstream/downloadhelper.cpp webengine/upstream/downloadhelper.h
            webengine/security.cpp webengine/security.h
    )
    find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS Network)
    target_include_directories(sailfishwebengineplugin PRIVATE webengine webengine/upstream)
    target_link_libraries(sailfishwebengineplugin PRIVATE Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick)
    keel_platform_install(sailfishwebengineplugin Sailfish/WebEngine)

    foreach(_f WebView.qml WebViewPage.qml WebViewFlickable.qml WebEngineBackend.qml ExternalBackend.qml)
        set_source_files_properties(webview/qml/${_f} PROPERTIES QT_RESOURCE_ALIAS ${_f})
    endforeach()
    # The backends are plain resources loaded by URL at run time: Qt WebEngine's
    # QML module may be missing, and WebView then falls back to the external one.
    qt_add_qml_module(sailfishwebviewplugin
        URI Sailfish.WebView
        RESOURCE_PREFIX /
        VERSION 1.0
        PLUGIN_TARGET sailfishwebviewplugin
        OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/WebView"
        DEPENDENCIES QtQuick Sailfish.Silica Sailfish.WebEngine
        QML_FILES webview/qml/WebView.qml webview/qml/WebViewPage.qml webview/qml/WebViewFlickable.qml
        RESOURCES webview/qml/WebEngineBackend.qml webview/qml/ExternalBackend.qml
    )
    add_dependencies(sailfishwebviewplugin sailfishwebengineplugin)
    keel_platform_install(sailfishwebviewplugin Sailfish/WebView)

    # sailfish-components-webview's Popups, Pickers and Controls (MPL-2.0,
    # webview/{popups,pickers,controls}; PROVENANCE.md), which Keel's WebView
    # drives from Qt WebEngine's requests (WebEngineBackend.qml).
    file(GLOB _webview_popups CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" webview/popups/*.qml)
    file(GLOB _webview_pickers CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" webview/pickers/*.qml)
    file(GLOB _webview_controls CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" webview/controls/*.qml)
    foreach(_f IN LISTS _webview_popups _webview_pickers _webview_controls)
        get_filename_component(_name "${_f}" NAME)
        set_source_files_properties(${_f} PROPERTIES QT_RESOURCE_ALIAS ${_name})
    endforeach()
    set_source_files_properties(webview/popups/StringUtils.js PROPERTIES
        QT_RESOURCE_ALIAS StringUtils.js QT_QML_SKIP_QMLDIR_ENTRY TRUE)
    set_source_files_properties(webview/popups/LocationSettings.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
    # Not in upstream's qmldir files.
    set_source_files_properties(webview/popups/ContextMenuItem.qml webview/pickers/DownloadPicker.qml
        webview/pickers/WebTimePickerDialog.qml PROPERTIES QT_QML_INTERNAL_TYPE TRUE)
    qt_add_qml_module(sailfishwebviewpopupsplugin
        URI Sailfish.WebView.Popups
        RESOURCE_PREFIX /
        VERSION 1.0
        PLUGIN_TARGET sailfishwebviewpopupsplugin
        OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/WebView/Popups"
        DEPENDENCIES QtQuick Sailfish.Silica Sailfish.WebEngine
        QML_FILES ${_webview_popups} webview/popups/StringUtils.js
    )
    keel_platform_install(sailfishwebviewpopupsplugin Sailfish/WebView/Popups)
    qt_add_qml_module(sailfishwebviewpickersplugin
        URI Sailfish.WebView.Pickers
        RESOURCE_PREFIX /
        VERSION 1.0
        PLUGIN_TARGET sailfishwebviewpickersplugin
        OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/WebView/Pickers"
        DEPENDENCIES QtQuick Sailfish.Silica Sailfish.Pickers
        QML_FILES ${_webview_pickers}
    )
    keel_platform_install(sailfishwebviewpickersplugin Sailfish/WebView/Pickers)
    qt_add_qml_module(sailfishwebviewcontrolsplugin
        URI Sailfish.WebView.Controls
        RESOURCE_PREFIX /
        VERSION 1.0
        PLUGIN_TARGET sailfishwebviewcontrolsplugin
        OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/WebView/Controls"
        DEPENDENCIES QtQuick Sailfish.Silica
        # Loaded with Controls, so that the permission types find WebEngine.
        IMPORTS Sailfish.WebEngine
        QML_FILES ${_webview_controls}
        SOURCES
            webview/controls/controlsforeign.h webview/controls/keelwebenginelink.h
            webview/controls/permissionmanager.cpp webview/controls/permissionmanager.h
            webview/controls/permissionmodel.cpp webview/controls/permissionmodel.h
            webview/controls/permissionfilterproxymodel.cpp webview/controls/permissionfilterproxymodel.h
    )
    target_include_directories(sailfishwebviewcontrolsplugin PRIVATE webview/controls)
    target_link_libraries(sailfishwebviewcontrolsplugin PRIVATE Qt6::Core Qt6::Qml)
    keel_platform_install(sailfishwebviewcontrolsplugin Sailfish/WebView/Controls)
    add_dependencies(sailfishwebviewplugin sailfishwebviewpopupsplugin sailfishwebviewpickersplugin
        sailfishwebviewcontrolsplugin)
    # Keel.WebEngine (ProfilePolicy), where Qt WebEngine is.
    add_subdirectory(webengine-policy)
endif()

# ---------------------------------------------------------------------------
# Sailfish.Secrets 1.0 and Sailfish.Crypto 1.0 (sailfish-secrets, BSD)
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_SECRETS "Build Sailfish.Secrets and Sailfish.Crypto (keel/platform/secrets)" ON)
if(KEEL_PLATFORM_SECRETS)
    add_subdirectory(secrets)
endif()

# ---------------------------------------------------------------------------
# Amber.Web.Authorization 1.0 (amber-web-authorization, BSD)
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_AMBER_WEB_AUTHORIZATION "Build Amber.Web.Authorization (keel/platform/amber-web-authorization)" ON)
if(KEEL_PLATFORM_AMBER_WEB_AUTHORIZATION)
    add_subdirectory(amber-web-authorization)
endif()

# ---------------------------------------------------------------------------
# org.nemomobile.mpris 1.0 (qtmpris, LGPL)
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_MPRIS "Build org.nemomobile.mpris (keel/platform/mpris)" ON)
if(KEEL_PLATFORM_MPRIS)
    add_subdirectory(mpris)
endif()

# ---------------------------------------------------------------------------
# Amber.Mpris 1.0 (amber-mpris, LGPL)
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_AMBER_MPRIS "Build Amber.Mpris (keel/platform/amber-mpris)" ON)
if(KEEL_PLATFORM_AMBER_MPRIS)
    add_subdirectory(amber-mpris)
endif()

# ---------------------------------------------------------------------------
# Nemo.Thumbnailer 1.0 (nemo-qml-plugin-thumbnailer, BSD)
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_THUMBNAILER "Build Nemo.Thumbnailer (keel/platform/thumbnailer)" ON)
if(KEEL_PLATFORM_THUMBNAILER)
    add_subdirectory(thumbnailer)
endif()

# ---------------------------------------------------------------------------
# Nemo.Mce 1.0 (libmce-qt, BSD)
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_MCE "Build Nemo.Mce (keel/platform/mce)" ON)
if(KEEL_PLATFORM_MCE)
    add_subdirectory(mce)
endif()

# ---------------------------------------------------------------------------
# libaccounts-qt6 and org.nemomobile.accounts 1.0 (only where libaccounts-glib
# is found; accounts/CMakeLists.txt checks)
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_ACCOUNTS "Build libaccounts-qt6 and org.nemomobile.accounts (keel/platform/accounts)" ON)
if(KEEL_PLATFORM_ACCOUNTS)
    add_subdirectory(accounts)
endif()
option(KEEL_PLATFORM_SAILFISH_ACCOUNTS "Build Sailfish.Accounts (keel/platform/sailfish-accounts)" ON)
if(KEEL_PLATFORM_ACCOUNTS AND KEEL_PLATFORM_SAILFISH_ACCOUNTS)
    add_subdirectory(sailfish-accounts)
endif()

# ---------------------------------------------------------------------------
# Sailfish.Policy 1.0 and libsailfishpolicy-qt6 (Keel's own, read only)
# ---------------------------------------------------------------------------
option(KEEL_PLATFORM_POLICY "Build Sailfish.Policy (keel/platform/policy)" ON)
if(KEEL_PLATFORM_POLICY)
    add_subdirectory(policy)
endif()

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
