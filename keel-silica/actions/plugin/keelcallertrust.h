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
//   - a process running with Sailfish OS's "privileged" group as its
//     effective group (/proc/<pid>/status), the platform's own mark of a
//     system component. pilotd is installed setgid privileged and starts
//     keel-mcp, which keeps that group; both are then not dumpable, so their
//     /proc/<pid>/exe cannot be read by an app and this is how they are
//     recognised on a device.
// Anything else (another app, a script, a process that starts keel-mcp
// itself; keel-mcp in turn believes only pilotd, keel/actions/mcp/src/peer.rs)
// reaches the app with userInitiated false. A process that cannot be
// inspected is not trusted.
//
// On the phone, inside Sailjail, this check cannot pass (Jolla Phone,
// 5.2.0.18, 11 October 2026): Firejail gives each sandboxed app its own PID
// namespace, so the host PID the bus daemon reports for the caller (keel-mcp
// included) names no process the app can see, and the app's own getpid() is
// not the host PID either. Sandboxed apps therefore always get userInitiated
// false: safe (it fails closed), and no Shoal app acts on the flag today,
// but no app may rely on it. The trust that holds on the device is
// keel-mcp's (peer.rs: it runs unsandboxed and checks its parent, pilotd);
// the fix for apps is a confirmation token minted by the on-device UI
// (docs: shipwright-assessment, Keel item 2).
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
