# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Test apps for the device kit tools/phase0/keel-runtime-test.sh (ADR-0016):
# Keel's direct-mode test app (Silica, keel/tests/direct), a plain QtQuick
# page for Qt 6 (tools/perf/qml), and their Qt 5 baselines for the phone's
# own Silica (sailfish-qml). Not for users.
#
#   mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=<you> \
#       -s keel/rpm/shipwright-keel-runtime-test.spec build
#
# Under mb2 the build runs in the checkout (the repository root).
Name:       shipwright-keel-runtime-test
Version:    0.1.0
Release:    4
Summary:    Test apps for Keel's runtime on a phone (direct mode, booster, keel-shell)
License:    MIT
URL:        https://github.com/shipwright/shipwright
Source0:    %{name}-%{version}.tar.bz2

BuildRequires:  gcc-c++
BuildRequires:  pkgconfig
BuildRequires:  cmake >= 3.19
BuildRequires:  ninja
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  qt6-qtdeclarative-devel >= 6.8
BuildRequires:  desktop-file-utils
Requires:       shipwright-keel-sailfishapp
Requires:       shipwright-keel-silica
# The Qt 5 baselines run on the phone's Silica.
Requires:       sailfishsilica-qt5
Requires:       mapplauncherd-booster-silica-qt5

%description
Test apps for tools/phase0/keel-runtime-test.sh: harbour-keeldirect (a
Silica page, cover, text field and list on Keel), harbour-keelplain (plain
QtQuick on Qt 6), keelnative and keelplain-qt5 (the same pages on the
phone's Qt 5 Silica, run with sailfish-qml). They print KEELTEST lines with
start-up and input-to-frame times.

%prep
%setup -q -n %{name}-%{version}

%build
# libkeel-sailfishapp from this same tree, built and staged first: the
# shipwright-keel-sailfishapp-devel package from the same CI build is not
# installable into mb2's build root (tools/build/sdk/build-rpms.sh).
%cmake -S keel -B build-keel-sailfishapp -G Ninja --no-warn-unused-cli \
    -DCMAKE_BUILD_TYPE=Release \
    -DKEEL_BUILD_SILICA=OFF \
    -DKEEL_BUILD_ACTIONS=OFF \
    -DKEEL_BUILD_NEMO_COMPAT=OFF \
    -DKEEL_BUILD_QT5COMPAT=OFF \
    -DKEEL_BUILD_PLATFORM=OFF \
    -DKEEL_BUILD_BOOSTER=OFF \
    -DBUILD_TESTING=OFF
cmake --build build-keel-sailfishapp %{?_smp_mflags}
DESTDIR=$PWD/sailfishapp-stage cmake --install build-keel-sailfishapp
stage=$PWD/sailfishapp-stage
# An SDK-template main() (SailfishApp::main), boostable: a PIE that exports
# main, as mapplauncherd requires.
g++ %{optflags} -std=c++17 -fPIE -pie -rdynamic \
    keel/sailfishapp/tests/probe/main.cpp \
    -I"$stage%{_includedir}/keel/sailfishapp" -L"$stage%{_libdir}" -lkeel-sailfishapp \
    $(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6Qml Qt6Quick) \
    -o harbour-keeldirect

%install
install -D -m 0755 harbour-keeldirect %{buildroot}%{_bindir}/harbour-keeldirect
# Keel picks the QML file by the binary's name (argv[0]). A hard link: one
# binary, one build-id.
ln %{buildroot}%{_bindir}/harbour-keeldirect %{buildroot}%{_bindir}/harbour-keelplain
install -D -m 0644 keel/tests/direct/data/qml/harbour-keeldirect.qml \
    %{buildroot}%{_datadir}/harbour-keeldirect/qml/harbour-keeldirect.qml
install -D -m 0644 tools/perf/qml/harbour-keelplain.qml \
    %{buildroot}%{_datadir}/harbour-keelplain/qml/harbour-keelplain.qml
install -D -m 0644 tools/phase0/keel-runtime/keelnative.qml \
    %{buildroot}%{_datadir}/keelnative/qml/keelnative.qml
install -D -m 0644 tools/perf/qml/harbour-keelplain.qml \
    %{buildroot}%{_datadir}/keelplain-qt5/qml/keelplain-qt5.qml
for app in harbour-keeldirect harbour-keelplain; do
    install -D -m 0644 tools/phase0/keel-runtime/$app.desktop \
        %{buildroot}%{_datadir}/applications/$app.desktop
    desktop-file-validate %{buildroot}%{_datadir}/applications/$app.desktop
done
install -D -m 0755 tools/phase0/keel-runtime-test.sh \
    %{buildroot}%{_datadir}/%{name}/keel-runtime-test.sh

%files
%{_bindir}/harbour-keeldirect
%{_bindir}/harbour-keelplain
%{_datadir}/harbour-keeldirect
%{_datadir}/harbour-keelplain
%{_datadir}/keelnative
%{_datadir}/keelplain-qt5
%{_datadir}/applications/harbour-keeldirect.desktop
%{_datadir}/applications/harbour-keelplain.desktop
%{_datadir}/%{name}
%license LICENSES/MIT.txt

%changelog
* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-4
- Licence: MIT (LICENSING.md).

* Sat Oct 03 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-3
- harbour-keelplain is a hard link to harbour-keeldirect, not a second copy.
* Fri Oct 02 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-2
- Build against libkeel-sailfishapp staged from the same tree.
* Thu Oct 01 2026 Shipwright <noreply@shipwright.invalid> - 0.1.0-1
- Device test apps for direct mode, booster-keel and keel-shell.
