# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Tests of Keel's platform modules, on the offscreen platform against the
# modules staged in ${KEEL_QML_OUTPUT_DIR}.

set(_keel_platform_test_env
    "QT_QPA_PLATFORM=offscreen"
    "QML_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR}"
    "QML2_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR}"
    "XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/runtime")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/runtime")
file(CHMOD "${CMAKE_CURRENT_BINARY_DIR}/runtime" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)

# Sailfish.Media: MediaKey's key filter and GRABBED_KEYS, MetadataReader's
# tag reading, and the QML types loading on Silica.
qt_add_executable(tst_keel_media media/tst_media.cpp)
target_compile_definitions(tst_keel_media PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
target_link_libraries(tst_keel_media PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test keelplatformcommon)
add_dependencies(tst_keel_media sailfishmediaplugin)
if(TARGET silicaplugin)
    add_dependencies(tst_keel_media silicaplugin)
endif()
add_test(NAME keel_platform_media COMMAND tst_keel_media)
set_tests_properties(keel_platform_media PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)

find_program(KEEL_DBUS_RUN_SESSION dbus-run-session)

if(KEEL_PLATFORM_PICKERS)
    # Sailfish.Pickers: the models on a fake home directory and the Tracker 3
    # source against a fake endpoint on a private bus; then the picker pages and
    # dialogs in a Silica ApplicationWindow on a fake home the test binary
    # writes (fixture).
    qt_add_executable(tst_keel_pickers pickers/tst_pickers.cpp)
    target_include_directories(tst_keel_pickers PRIVATE ../pickers)
    target_compile_definitions(tst_keel_pickers PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
    target_sources(tst_keel_pickers PRIVATE ../pickers/trackersource.cpp ../pickers/contentitem.cpp)
    target_link_libraries(tst_keel_pickers PRIVATE Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Test keelplatformcommon)
    add_dependencies(tst_keel_pickers sailfishpickersplugin)
    if(TARGET silicaplugin)
        add_dependencies(tst_keel_pickers silicaplugin)
    endif()
    if(KEEL_DBUS_RUN_SESSION)
        add_test(NAME keel_platform_pickers COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_pickers>)
    else()
        add_test(NAME keel_platform_pickers COMMAND tst_keel_pickers)
    endif()
    set_tests_properties(keel_platform_pickers PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)

    set(_pickers_home "${CMAKE_CURRENT_BINARY_DIR}/pickers-home")
    add_test(NAME keel_platform_pickers_fixture
        COMMAND ${CMAKE_COMMAND} -E env QT_QPA_PLATFORM=offscreen
                $<TARGET_FILE:tst_keel_pickers> --make-fixture "${_pickers_home}")
    set_tests_properties(keel_platform_pickers_fixture PROPERTIES FIXTURES_SETUP keel_pickers_home)
    add_test(NAME keel_platform_pickers_qml
        COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/pickers/qml")
    set_tests_properties(keel_platform_pickers_qml PROPERTIES
        FIXTURES_REQUIRED keel_pickers_home
        ENVIRONMENT "${_keel_platform_test_env};HOME=${_pickers_home};USER=keel-test-nobody;KEEL_PICKERS_TRACKER=0;XDG_CONFIG_HOME=${_pickers_home}/.config"
        TIMEOUT 120)
endif()

# Sailfish.Secrets / Sailfish.Crypto (sailfish-secrets for Qt 6) against a
# fake sailfishsecretsd on a private bus, and the Qt 5 key format.
if(KEEL_PLATFORM_SECRETS AND KEEL_DBUS_RUN_SESSION)
    qt_add_executable(tst_keel_secrets secrets/tst_secrets.cpp)
    target_compile_definitions(tst_keel_secrets PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
    target_compile_options(tst_keel_secrets PRIVATE -Wno-deprecated-declarations)
    target_link_libraries(tst_keel_secrets PRIVATE sailfishcrypto-qt6 Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Test)
    add_dependencies(tst_keel_secrets sailfishsecretsplugin sailfishcryptoplugin)
    add_test(NAME keel_platform_secrets COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_secrets>)
    set_tests_properties(keel_platform_secrets PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# libaccounts-qt6 / org.nemomobile.accounts on a private accounts database,
# when libaccounts-glib was found (on Ubuntu: libaccounts-glib-dev).
if(TARGET nemoaccounts)
    # accounts-qt6 links Qt6::Xml; imported targets are per directory.
    find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS Xml)
endif()
if(TARGET nemoaccounts AND KEEL_DBUS_RUN_SESSION)
    qt_add_executable(tst_keel_accounts accounts/tst_accounts.cpp)
    target_compile_definitions(tst_keel_accounts PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}"
        KEEL_ACCOUNTS_DATA="${CMAKE_CURRENT_SOURCE_DIR}/accounts/data")
    target_link_libraries(tst_keel_accounts PRIVATE accounts-qt6 Qt6::Core Qt6::Gui Qt6::Qml Qt6::Test)
    add_dependencies(tst_keel_accounts nemoaccounts)
    add_test(NAME keel_platform_accounts COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_accounts>)
    set_tests_properties(keel_platform_accounts PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# Sailfish.Accounts on a private accounts database and bus, with a fake
# signond on its peer-to-peer socket.
if(TARGET sailfishaccountsplugin AND KEEL_DBUS_RUN_SESSION)
    qt_add_executable(tst_keel_sailfishaccounts sailfish-accounts/tst_sailfishaccounts.cpp)
    target_compile_definitions(tst_keel_sailfishaccounts PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}"
        KEEL_ACCOUNTS_DATA="${CMAKE_CURRENT_SOURCE_DIR}/accounts/data")
    target_link_libraries(tst_keel_sailfishaccounts PRIVATE accounts-qt6 Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Test)
    add_dependencies(tst_keel_sailfishaccounts sailfishaccountsplugin)
    add_test(NAME keel_platform_sailfish_accounts
        COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_sailfishaccounts>)
    set_tests_properties(keel_platform_sailfish_accounts PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# Sailfish.Gallery: ThumbnailImage and ImageViewer on Silica.
if(KEEL_PLATFORM_GALLERY)
    add_test(NAME keel_platform_gallery_qml
        COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/gallery")
    set_tests_properties(keel_platform_gallery_qml PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# Sailfish.Media's MprisPlayerControls as the lock screen uses it, against
# a fake MPRIS player on a private session bus.
if(KEEL_PLATFORM_AMBER_MPRIS AND KEEL_DBUS_RUN_SESSION)
    qt_add_executable(tst_keel_mprisplayercontrols media/tst_mprisplayercontrols.cpp)
    target_compile_definitions(tst_keel_mprisplayercontrols PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}"
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/media")
    target_link_libraries(tst_keel_mprisplayercontrols PRIVATE Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Quick Qt6::Test)
    add_dependencies(tst_keel_mprisplayercontrols sailfishmediaplugin ambermprisplugin)
    add_test(NAME keel_platform_mpris_player_controls
        COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_mprisplayercontrols>)
    set_tests_properties(keel_platform_mpris_player_controls PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# Sailfish.Policy against a fake policy store and privacy switch daemon on
# a private session bus.
if(TARGET sailfishpolicyplugin AND KEEL_DBUS_RUN_SESSION)
    qt_add_executable(tst_keel_sailfishpolicy policy/tst_sailfishpolicy.cpp)
    target_compile_definitions(tst_keel_sailfishpolicy PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
    target_link_libraries(tst_keel_sailfishpolicy PRIVATE sailfishpolicy-qt6 Qt6::Core Qt6::DBus Qt6::Qml Qt6::Test)
    add_dependencies(tst_keel_sailfishpolicy sailfishpolicyplugin)
    add_test(NAME keel_platform_sailfish_policy
        COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_sailfishpolicy>)
    set_tests_properties(keel_platform_sailfish_policy PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# Sailfish.WebView / Sailfish.WebEngine: over a test double of Qt WebEngine's
# QML module (webview/fake), and the external fallback where Qt WebEngine is
# missing (forced with KEEL_WEBVIEW_BACKEND where a host has it).
if(KEEL_PLATFORM_WEBVIEW)
    add_test(NAME keel_platform_webview_engine
        COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
                -import "${CMAKE_CURRENT_SOURCE_DIR}/webview/fake"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/webview/qml-engine")
    # Remembered site permissions go to the build tree, not the user's data.
    set(_keel_webview_env "${_keel_platform_test_env}"
        "KEEL_WEBVIEW_PERMISSIONS=${CMAKE_CURRENT_BINARY_DIR}/webview-permissions.json"
        # No TLS connections of the WebView's own to the test URLs' hosts.
        "KEEL_WEBVIEW_CERTIFICATES=0")
    # Sailfish.WebView.Popups, .Pickers and .Controls through the message
    # bridge, in a process of its own: a test that loads Sailfish.WebEngine
    # first registers the real Qt WebEngine types over the test double's.
    add_test(NAME keel_platform_webview_popups
        COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
                -import "${CMAKE_CURRENT_SOURCE_DIR}/webview/fake"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/webview/qml-popups")
    set_tests_properties(keel_platform_webview_popups PROPERTIES ENVIRONMENT "${_keel_webview_env}" TIMEOUT 120
                         FIXTURES_REQUIRED keel_webview_permissions)
    # The rest of the WebView and WebEngine API, in a process of its own too
    # (a test file compiled after Keel.WebEngine has loaded the real Qt
    # WebEngine would get its types).
    add_test(NAME keel_platform_webview_api
        COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
                -import "${CMAKE_CURRENT_SOURCE_DIR}/webview/fake"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/webview/qml-api")
    set_tests_properties(keel_platform_webview_api PROPERTIES ENVIRONMENT "${_keel_webview_env}" TIMEOUT 120)
    add_test(NAME keel_platform_webview_permissions_reset
        COMMAND ${CMAKE_COMMAND} -E rm -f "${CMAKE_CURRENT_BINARY_DIR}/webview-permissions.json")
    set_tests_properties(keel_platform_webview_permissions_reset PROPERTIES FIXTURES_SETUP keel_webview_permissions)
    set_tests_properties(keel_platform_webview_engine PROPERTIES ENVIRONMENT "${_keel_webview_env}" TIMEOUT 120)
    get_target_property(_keel_qmake Qt6::qmake IMPORTED_LOCATION)
    execute_process(COMMAND "${_keel_qmake}" -query QT_INSTALL_QML
                    OUTPUT_VARIABLE _keel_host_qml OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(_keel_host_qtwebengine OFF)
    if(EXISTS "${_keel_host_qml}/QtWebEngine/qmldir")
        set(_keel_host_qtwebengine ON)
    endif()
    set(_keel_external_env "${_keel_webview_env}")
    if(_keel_host_qtwebengine)
        list(APPEND _keel_external_env "KEEL_WEBVIEW_BACKEND=external")
    endif()
    add_test(NAME keel_platform_webview_external
        COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/webview/qml-external")
    set_tests_properties(keel_platform_webview_external PROPERTIES ENVIRONMENT "${_keel_external_env}" TIMEOUT 120)
    # The real Qt WebEngine (offscreen, no sandbox) against a local HTTP
    # server, where Keel.WebEngine was built.
    if(TARGET keelwebengineplugin)
        find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS Network WebEngineQuick)
        qt_add_executable(tst_keel_webview_qtwebengine webview/qtwebengine/tst_webview_qtwebengine.cpp)
        target_compile_definitions(tst_keel_webview_qtwebengine PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
        target_link_libraries(tst_keel_webview_qtwebengine PRIVATE
            Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick Qt6::Test Qt6::WebEngineQuick)
        add_dependencies(tst_keel_webview_qtwebengine keelwebengineplugin)
        add_test(NAME keel_platform_webview_qtwebengine COMMAND tst_keel_webview_qtwebengine)
        set_tests_properties(keel_platform_webview_qtwebengine PROPERTIES ENVIRONMENT "${_keel_webview_env}" TIMEOUT 180)
    endif()
endif()

# org.nemomobile.mpris (qtmpris for Qt 6) on a private bus, with a plain
# D-Bus MPRIS client.
if(KEEL_PLATFORM_MPRIS AND KEEL_DBUS_RUN_SESSION)
    qt_add_executable(tst_keel_mpris mpris/tst_mpris.cpp)
    target_compile_definitions(tst_keel_mpris PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
    target_link_libraries(tst_keel_mpris PRIVATE Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Test)
    add_dependencies(tst_keel_mpris mprisplugin)
    add_test(NAME keel_platform_mpris COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_mpris>)
    set_tests_properties(keel_platform_mpris PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# Amber.Mpris (amber-mpris for Qt 6) on a private bus: a plain D-Bus MPRIS
# client against an MprisPlayer, an MprisController against a plain D-Bus
# player.
if(KEEL_PLATFORM_AMBER_MPRIS AND KEEL_DBUS_RUN_SESSION)
    qt_add_executable(tst_keel_ambermpris amber-mpris/tst_ambermpris.cpp)
    target_compile_definitions(tst_keel_ambermpris PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
    target_link_libraries(tst_keel_ambermpris PRIVATE Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Test)
    add_dependencies(tst_keel_ambermpris ambermprisplugin)
    add_test(NAME keel_platform_amber_mpris COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_ambermpris>)
    set_tests_properties(keel_platform_amber_mpris PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# Nemo.Thumbnailer (nemo-qml-plugin-thumbnailer for Qt 6), offscreen with a
# private thumbnail cache.
if(KEEL_PLATFORM_THUMBNAILER)
    qt_add_executable(tst_keel_thumbnailer thumbnailer/tst_thumbnailer.cpp)
    target_compile_definitions(tst_keel_thumbnailer PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}"
        QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/thumbnailer")
    target_link_libraries(tst_keel_thumbnailer PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
    add_dependencies(tst_keel_thumbnailer nemothumbnailer)
    add_test(NAME keel_platform_thumbnailer COMMAND tst_keel_thumbnailer
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/thumbnailer")
    set_tests_properties(keel_platform_thumbnailer PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# Nemo.Mce (libmce-qt for Qt 6) against a fake MCE on a private bus.
if(KEEL_PLATFORM_MCE AND KEEL_DBUS_RUN_SESSION)
    qt_add_executable(tst_keel_mce mce/tst_mce.cpp)
    target_compile_definitions(tst_keel_mce PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
    target_link_libraries(tst_keel_mce PRIVATE Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Test)
    add_dependencies(tst_keel_mce qmcedeclarative)
    add_test(NAME keel_platform_mce COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_mce>)
    set_tests_properties(keel_platform_mce PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()

# Amber.Web.Authorization (amber-web-authorization for Qt 6) as
# sfos-forum-viewer's login uses it.
if(KEEL_PLATFORM_AMBER_WEB_AUTHORIZATION)
    find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS Network)
    qt_add_executable(tst_keel_amber amber/tst_amber.cpp)
    target_compile_definitions(tst_keel_amber PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
    target_link_libraries(tst_keel_amber PRIVATE Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Test)
    add_dependencies(tst_keel_amber amberwebauthorizationplugin)
    add_test(NAME keel_platform_amber COMMAND tst_keel_amber)
    set_tests_properties(keel_platform_amber PROPERTIES ENVIRONMENT "${_keel_platform_test_env}" TIMEOUT 120)
endif()
