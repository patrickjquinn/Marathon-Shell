# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT

# keel-mcp (ADR-0018): the MCP server for every Keel app's actions, run by
# Pilot as `/usr/bin/keel-mcp --stdio` (or listening on a Unix socket).
# Built by tools/build/sdk/build-rpms.sh: the binary is cross-compiled
# beforehand into target/<arch>-unknown-linux-gnu/release/ from the root
# workspace with the pinned rustup toolchain (keel-mcp needs Rust 1.88),
# and mb2 runs this spec from the repository root (%%{_builddir}). Never
# call cargo here: the in-SDK Rust is 1.75.

%{!?keel_mcp_bin: %global keel_mcp_bin target/%{_arch}-unknown-linux-gnu/release/keel-mcp}
# Prebuilt, already stripped by the release profile.
%global debug_package %{nil}
%global _build_id_links none

Name:       shipwright-keel-mcp
Summary:    MCP server for the Keel Actions of the apps on the device
Version:    0.1.0
Release:    2
License:    MIT
URL:        https://github.com/shipwright/shipwright

# Apps are reached on the session bus; their manifests are installed under
# /usr/share/keel/actions by each app's package (with the Keel.Actions
# runtime, shipwright-keel-actions).
Requires:   dbus
Recommends: shipwright-keel-actions

%description
keel-mcp serves the actions, entities, context and shortcuts that Keel
apps declare (Keel Actions) as one Model Context Protocol server. It reads
the manifests installed in /usr/share/keel/actions and asks running apps
for theirs, validates every call against the declared schemas, and calls
the apps over D-Bus (org.shipwright.Keel.Actions), starting them without
their window when needed. Sensitive results never go to a model, and an
app's context is read only for a request the person started.

It speaks MCP over stdin and stdout (for a client that starts it, such as
Pilot) or on a Unix socket in the session's runtime directory.

%prep

%build

%install
if [ ! -x %{keel_mcp_bin} ]; then
    echo "%{keel_mcp_bin} is missing: cross-build the root workspace first (tools/build/sdk/cargo-sailfish.sh)" >&2
    exit 1
fi
install -D -m 0755 %{keel_mcp_bin} %{buildroot}%{_bindir}/keel-mcp
install -d %{buildroot}%{_datadir}/keel/actions

%files
%license LICENSES/MIT.txt
%{_bindir}/keel-mcp
%dir %{_datadir}/keel
%dir %{_datadir}/keel/actions

%changelog
* Sat Oct 03 2026 Shipwright - 0.1.0-2
- Licence: MIT (LICENSING.md).

* Fri Oct 02 2026 Shipwright - 0.1.0-1
- First package: keel-mcp on stdio and a Unix socket (ADR-0018).
