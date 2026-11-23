// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Who may tell an app that the person started a request (Invoke's
// `userInitiated`). The claim is believed from the caller's process, never
// from the call: the D-Bus sender's process id (from the bus daemon, which
// the caller cannot choose) must be
//   - this app's own process,
//   - a known executable (/usr/bin/pilotd, /usr/bin/keel-mcp), compared by
//     file (device and inode of /proc/<pid>/exe), so neither argv[0] nor a
//     lookalike path passes, or
//   - on Sailfish OS, a process with the "privileged" group as its
//     effective or saved group: there pilotd is installed setgid privileged
//     (which also makes it non-dumpable, so its /proc/<pid>/exe cannot be
//     read) and keel-mcp keeps the group. Marathon has no such group and
//     ships pilotd 0755: setgid would make it non-dumpable, and the shell
//     admits pilotd to its services by reading /proc/<pid>/exe.
// Anything else (another app, a script, a process that starts keel-mcp
// itself; keel-mcp in turn believes only pilotd, keel/actions/mcp/src/peer.rs)
// reaches the app with userInitiated false. A process that cannot be
// inspected is not trusted.
//
// This check needs the system's view of processes. An app in a PID
// namespace of its own (bubblewrap on Marathon, Firejail under Sailjail)
// sees none of them: the bus daemon's process id names no process there,
// or one of the app's own. Such an app asks the Marathon shell instead
// (Permissions1.SpeaksForPerson, keeladaptor.cpp), which recognises pilotd
// by its unit and executable and keel-mcp as pilotd's child. Without a
// shell to ask (Sailjail) a sandboxed app believes only itself.
#ifndef KEEL_ACTIONS_CALLERTRUST_H
#define KEEL_ACTIONS_CALLERTRUST_H

#include <QString>
#include <QStringList>

#include <optional>

namespace KeelCallerTrust {

// The executables trusted by file.
QStringList trustedExecutables();

// Whether process `pid` may say the person started a request.
bool isTrusted(qint64 pid);

// Whether this process sees the system's processes: false in a sandbox
// with a PID namespace of its own, where the bus daemon's process ids name
// no process this one can inspect.
bool inInitialPidNamespace();

// Whether process `pid` runs one of `paths` (the same file).
bool runsOneOf(qint64 pid, const QStringList &paths);

// The effective group of process `pid`, from /proc/<pid>/status.
std::optional<uint> effectiveGid(qint64 pid);
// The saved group of `pid`.
std::optional<uint> savedGid(qint64 pid);

// The id of the "privileged" group, if the system has one.
std::optional<uint> privilegedGid();

} // namespace KeelCallerTrust

#endif
