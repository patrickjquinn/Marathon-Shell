# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# pacific-minibrowser: a small test app for Shipwright.Pacific.WebView, run on
# the host and on the phone (README.md "Running").
qt_add_executable(pacific-minibrowser main.cpp)
qt_add_qml_module(pacific-minibrowser
    URI PacificMiniBrowser
    VERSION 1.0
    QML_FILES Main.qml SilicaMain.qml
    NO_RESOURCE_TARGET_PATH
)
target_link_libraries(pacific-minibrowser PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick)
install(TARGETS pacific-minibrowser RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
