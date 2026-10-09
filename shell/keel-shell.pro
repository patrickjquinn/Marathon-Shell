# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Sailfish OS build of keel-shell against the system Qt 5.6.3 and its
# QtCompositor module (qt5-qtwayland-wayland_egl-devel), like qt-runner.
# Host builds use CMakeLists.txt (Qt 5.15 backend).

TEMPLATE = app
TARGET = keel-shell

isEmpty(PREFIX): PREFIX = /usr
isEmpty(VERSION): VERSION = 0.1.0
# Library directory that holds keel/qt5compat (%{_libdir}). Qt's own library
# directory is /usr/lib64 on aarch64 and /usr/lib on armv7hl and i486, as
# %{_libdir} is; the spec may also pass KEEL_LIBDIR=%{_libdir}.
isEmpty(KEEL_LIBDIR): KEEL_LIBDIR = $$[QT_INSTALL_LIBS]

QT += core gui gui-private quick dbus compositor compositor-private
CONFIG += c++14 link_pkgconfig
CONFIG -= app_bundle

DEFINES += QT_COMPOSITOR_QUICK KEEL_BACKEND_QT56
DEFINES += KEEL_SHELL_VERSION=\\\"$$VERSION\\\"
DEFINES += KEEL_QT5COMPAT_DIR=\\\"$$KEEL_LIBDIR/keel/qt5compat\\\"

INCLUDEPATH += src

HEADERS += \
    src/core/ambience.h \
    src/core/backend.h \
    src/core/containerstate.h \
    src/core/coverpolicy.h \
    src/core/graphics.h \
    src/core/launchconfig.h \
    src/core/lipstickwindow.h \
    src/core/logging.h \
    src/core/orientation.h \
    src/core/runner.h \
    src/core/shellservice.h \
    src/core/shellstate.h \
    src/core/surfaceinfo.h \
    src/core/unixsignals.h \
    src/core/windowmapper.h \
    src/backend/qt56/backend56.h

SOURCES += \
    src/main.cpp \
    src/core/ambience.cpp \
    src/core/backend.cpp \
    src/core/containerstate.cpp \
    src/core/coverpolicy.cpp \
    src/core/graphics.cpp \
    src/core/launchconfig.cpp \
    src/core/lipstickwindow.cpp \
    src/core/logging.cpp \
    src/core/orientation.cpp \
    src/core/runner.cpp \
    src/core/shellservice.cpp \
    src/core/shellstate.cpp \
    src/core/unixsignals.cpp \
    src/core/windowmapper.cpp \
    src/backend/qt56/backend56.cpp

target.path = $$PREFIX/bin
INSTALLS += target

# Installed by qmake (not %doc/%license) so mb2 shadow builds work.
docs.files = README.md PROTOCOL.md PROVENANCE.md
docs.path = $$PREFIX/share/doc/shipwright-keel-shell
licenses.files = upstream-licenses/qt-runner.LICENSE upstream-licenses/newcompositor.LICENSE
licenses.path = $$PREFIX/share/licenses/shipwright-keel-shell
INSTALLS += docs licenses

OTHER_FILES += \
    README.md \
    PROTOCOL.md \
    PROVENANCE.md \
    rpm/shipwright-keel-shell.spec \
    packaging/keel-app.desktop.example
