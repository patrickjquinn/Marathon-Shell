#pragma once

#include <QLatin1StringView>
#include <QString>

// The prebuilt Android image's composer names an app's window
// "waydroid.<package>" and Android's own full-screen window "Waydroid"; the
// shell knows the app as "deckard.<package>". Renamed with Deckard's image.
namespace AndroidAppId {

    inline constexpr QLatin1StringView composerPrefix{"waydroid."};
    inline constexpr QLatin1StringView prefix{"deckard."};
    inline constexpr QLatin1StringView fullScreen{"Waydroid"};

    // The shell's id for a window's app id.
    inline QString canonical(const QString &appId) {
        return appId.startsWith(composerPrefix) ? prefix + appId.mid(composerPrefix.size())
                                                : appId;
    }

    // A window of Android's: an app's or Android's own.
    inline bool isAndroid(const QString &appId) {
        return appId == fullScreen || appId.startsWith(prefix);
    }

} // namespace AndroidAppId
