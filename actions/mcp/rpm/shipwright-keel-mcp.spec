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
Release:    10
License:    MIT
URL:        https://github.com/patrickjquinn/shipwright-open

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
* Sat Oct 17 2026 Shipwright - 0.1.0-10
- Rebuilt with Keel 0.1.0-34; no change in behaviour.
* Fri Oct 16 2026 Shipwright - 0.1.0-9
- Lists every app's built-in app.show, which brings the app to the front and can open one of its pages.
* Wed Oct 14 2026 Shipwright - 0.1.0-8
- Asking an app that has never been opened (so its permissions were never allowed) answers at once that it has to be opened first, instead of timing out after a minute.
- Looking for running apps no longer asks every program on the phone every 10 seconds; each is asked once, and again only when it restarts.

* Mon Oct 12 2026 Shipwright - 0.1.0-7
- An app's action that changes things the person must confirm (installing,
  removing, deleting) runs only for a client that speaks for the person, as
  plans already did: a paired computer or an untrusted local client can no
  longer run one on its own.

* Sun Oct 11 2026 Shipwright - 0.1.0-6
- Recognises Pilot by its saved privileged group too: Pilot now runs as the person's group and raises its rights only to read the calendar and contacts.

* Sun Oct 11 2026 Shipwright - 0.1.0-5
- Only Pilot speaks for the person: what a client says the person started or confirmed is believed only from pilotd (or another process in the privileged group); any other client's calls reach apps as the apps' own requests, its plans that need confirmation are refused, and it cannot read an app's context.
- The socket (--socket) is created with mode 0600 from the start: it is bound in a private directory and moved into place.

* Sun Oct 11 2026 Shipwright - 0.1.0-4
- A paired computer (--external) cannot speak for the person: what it says the person started or confirmed is not believed, and a plan with a step that needs confirmation is refused.
- Each connection may make 60 tool calls in 10 seconds.
- Clients are told when the tools, prompts or resources change (listChanged; subscriptions/listen in MCP 2026-07-28).
- A batch or a request with a null id is answered with Invalid Request (-32600); a null id ended the session.
- A tool whose name MCP clients would refuse (over 128 characters, or other than letters, digits, _ - .) is left out.

* Sun Oct 11 2026 Shipwright - 0.1.0-3
- MCP 2026-07-28: every result says resultType "complete", and lists and reads say how long they may be cached (ttlMs, cacheScope private).
- A sensitive tool no longer declares an outputSchema it never fills (its result is for the person, never structured content).
- An app that does not answer, or cannot be reached, is a server error, not "not found"; a malformed plan is a tool error the model can correct.

* Sat Oct 03 2026 Shipwright - 0.1.0-2
- Licence: MIT (LICENSING.md).

* Fri Oct 02 2026 Shipwright - 0.1.0-1
- First package: keel-mcp on stdio and a Unix socket (ADR-0018).
