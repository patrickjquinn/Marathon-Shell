#pragma once

#include <QStringList>

// A Sailfish app's [X-Sailjail] permissions as a bubblewrap sandbox, in
// place of Sailfish's firejail profiles (sailfishos/sailjail-permissions).
namespace Sailjail {

// bwrap arguments up to, not including, the command.
QStringList bwrapArgs(const QStringList &permissions, const QString &organization,
                      const QString &application, const QString &home, const QString &runtimeDir);

} // namespace Sailjail
