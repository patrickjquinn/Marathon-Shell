## Battery warnings

battery-low-title = Battery Low
battery-low-body = { $level }% remaining
battery-lower-title = Low Battery
battery-lower-body = { $level }% remaining. Connect charger soon.
battery-very-low-title = Very Low Battery
battery-very-low-body = { $level }% remaining. Connect charger immediately.
battery-critical-title = Critical Battery
# $action is what the device does next: PowerOff, Hibernate or HybridSleep.
battery-critical-body = { $action ->
    [Hibernate] Device will hibernate in 10 seconds to prevent data loss
    [HybridSleep] Device will hibernate in 10 seconds to prevent data loss
   *[other] Device will turn off in 10 seconds to prevent data loss
}

## Bluetooth, location and the modem

bluetooth-unknown-device = Unknown Device
location-client-failed = Failed to create location client
location-start-failed = Failed to start location updates
modem-none = No modem available

## Wi-Fi and the hotspot

network-rejected = Connection rejected by NetworkManager (bad config)
network-wrong-password = Incorrect password
network-timeout = Connection timeout
network-not-found = Network not found
# $message is NetworkManager's own reason, in English.
network-failed-because = Failed: { $message }
# $name is NetworkManager's error name.
network-failed-named = Failed ({ $name })
network-couldnt-connect = Couldn't connect
wifi-enable-failed = Failed to enable WiFi
wifi-disable-failed = Failed to disable WiFi
wifi-disconnect-failed = Failed to disconnect Wi-Fi
wifi-scan-failed = Failed to scan for networks
wifi-unavailable = WiFi not available
hotspot-failed = The Wi-Fi adapter could not start an access point

## Permissions, push, search and sharing

permission-unknown = Unknown permission
push-new = New push notification
# Under an app's name in search results.
search-native-app = Native App
search-marathon-app = Marathon App
share-not-taken = The app did not take the share

## Unlocking

security-pin-empty = PIN cannot be empty
security-password-empty = Password cannot be empty
security-busy = Authentication already in progress
security-account-locked = Account locked. Try again in { $seconds ->
    [one] { $seconds } second
   *[other] { $seconds } seconds
}.
security-locked-for = Too many failed attempts. Locked for { $seconds ->
    [one] { $seconds } second
   *[other] { $seconds } seconds
}.
security-try-again-in = Too many failed attempts. Try again in { $seconds ->
    [one] { $seconds } second
   *[other] { $seconds } seconds
}.
security-wrong-pin = Incorrect PIN
security-wrong-password = Incorrect password
security-wrong-pin-left = Incorrect PIN ({ $remaining ->
    [one] { $remaining } attempt remaining
   *[other] { $remaining } attempts remaining
})
security-wrong-password-left = Incorrect password ({ $remaining ->
    [one] { $remaining } attempt remaining
   *[other] { $remaining } attempts remaining
})
security-set-pin-password = System password incorrect. Cannot set Quick PIN.
security-remove-pin-password = System password incorrect. Cannot remove Quick PIN.
security-startup-pin-change-failed = Couldn't change the PIN that unlocks your data at startup
security-startup-pin-off-failed = Couldn't turn off the PIN that unlocks your data at startup
security-biometric-unsupported = Biometric type not supported
security-cannot-erase = This device can't erase itself
# $error is the system's own reason, in English.
security-erase-unreachable = Couldn't reach the erase service: { $error }
security-erase-closed = Couldn't reach the erase service: it closed the connection

## The fingerprint reader

fingerprint-unavailable = Fingerprint not available
fingerprint-not-recognised = Fingerprint not recognized
fingerprint-busy = Fingerprint device busy
fingerprint-start-failed = Fingerprint verification failed to start
fingerprint-place = Place your finger on the sensor
fingerprint-retry-scan = Scan quality poor, try again
fingerprint-too-short = Swipe too short, try again
fingerprint-centre = Center your finger and try again
fingerprint-remove = Remove finger and try again

## Software updates

# The notification's app name.
update-app = Software update
update-open = Open
update-download = Download
update-later = Later
update-restart-now = Restart now
update-tonight = Tonight
update-available-title = Update available
update-available-body = Marathon { $version }
update-restart-title = Restart to finish updating
update-restart-tonight = Marathon { $version } installs tonight while charging.
update-restart-ready = Marathon { $version } is ready.
update-rolled-back-title = Marathon { $version } didn't start
# $previous is the version it went back to.
update-rolled-back-body = The update couldn't start, so Marathon went back to { $previous }.
update-updated-title = Updated to Marathon { $version }
update-updated-body = Tap to see what's new.
update-installing = Installing update
update-downloading = Downloading update
update-progress = Marathon OS { $version } · { $percent }%

## Weather

weather-timed-out = Timed out
