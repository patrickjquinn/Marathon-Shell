pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: audioManager
    
    property real volume: 0.6
    property real minVolume: 0.0
    property real maxVolume: 1.0
    
    property bool muted: false
    property bool vibrationEnabled: true
    property bool dndEnabled: false
    
    property string audioProfile: "normal"
    property var availableProfiles: ["silent", "vibrate", "normal", "loud"]
    
    property string audioOutput: "speaker"
    property var availableOutputs: ["speaker", "headphones", "bluetooth", "usb"]
    
    property bool headphonesConnected: false
    property bool bluetoothAudioConnected: false
    
    property real mediaVolume: 0.6
    property real ringtoneVolume: 0.8
    property real alarmVolume: 0.9
    property real notificationVolume: 0.7
    property real systemVolume: 0.5
    
    // Sound file properties
    property string currentRingtone: SettingsManagerCpp.ringtone
    property string currentNotificationSound: SettingsManagerCpp.notificationSound
    property string currentAlarmSound: SettingsManagerCpp.alarmSound
    
    // Available sounds (computed once)
    readonly property var availableRingtones: SettingsManagerCpp.availableRingtones()
    readonly property var availableNotificationSounds: SettingsManagerCpp.availableNotificationSounds()
    readonly property var availableAlarmSounds: SettingsManagerCpp.availableAlarmSounds()
    
    // Friendly names for UI display
    readonly property string currentRingtoneName: SettingsManagerCpp.formatSoundName(currentRingtone)
    readonly property string currentNotificationSoundName: SettingsManagerCpp.formatSoundName(currentNotificationSound)
    readonly property string currentAlarmSoundName: SettingsManagerCpp.formatSoundName(currentAlarmSound)
    
    signal volumeSet(real value)
    signal muteToggled(bool muted)
    signal profileChanged(string profile)
    signal outputChanged(string output)
    signal headphonesStateChanged(bool connected)
    
    function setRingtone(path) {
        currentRingtone = path
        SettingsManagerCpp.ringtone = path
    }
    
    function setNotificationSound(path) {
        currentNotificationSound = path
        SettingsManagerCpp.notificationSound = path
    }
    
    function setAlarmSound(path) {
        currentAlarmSound = path
        SettingsManagerCpp.alarmSound = path
    }
    
    function setVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value))
        console.log("[AudioManager] Setting volume:", clamped)
        volume = clamped
        volumeSet(clamped)
        _platformSetVolume(clamped)
    }
    
    function increaseVolume(step) {
        setVolume(volume + (step || 0.1))
    }
    
    function decreaseVolume(step) {
        setVolume(volume - (step || 0.1))
    }
    
    function setMuted(mute) {
        console.log("[AudioManager] Muted:", mute)
        muted = mute
        muteToggled(mute)
        _platformSetMuted(mute)
    }
    
    function toggleMute() {
        setMuted(!muted)
    }
    
    function setAudioProfile(profile) {
        if (availableProfiles.indexOf(profile) === -1) {
            console.warn("[AudioManager] Invalid audio profile:", profile)
            return
        }
        
        console.log("[AudioManager] Audio profile:", profile)
        audioProfile = profile
        
        switch (profile) {
            case "silent":
                setMuted(true)
                vibrationEnabled = false
                break
            case "vibrate":
                setMuted(true)
                vibrationEnabled = true
                break
            case "normal":
                setMuted(false)
                vibrationEnabled = true
                break
            case "loud":
                setMuted(false)
                vibrationEnabled = true
                setVolume(0.9)
                break
        }
        
        profileChanged(profile)
        _platformSetAudioProfile(profile)
    }
    
    function setVibration(enabled) {
        console.log("[AudioManager] Vibration:", enabled)
        vibrationEnabled = enabled
        _platformSetVibration(enabled)
    }
    
    function setDoNotDisturb(enabled) {
        console.log("[AudioManager] Do Not Disturb:", enabled)
        dndEnabled = enabled
        _platformSetDoNotDisturb(enabled)
    }
    
    function setMediaVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value))
        mediaVolume = clamped
        _platformSetStreamVolume("media", clamped)
    }
    
    function setRingtoneVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value))
        ringtoneVolume = clamped
        _platformSetStreamVolume("ringtone", clamped)
    }
    
    function setAlarmVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value))
        alarmVolume = clamped
        _platformSetStreamVolume("alarm", clamped)
    }
    
    function setNotificationVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value))
        notificationVolume = clamped
        _platformSetStreamVolume("notification", clamped)
    }
    
    function playSound(soundType) {
        console.log("[AudioManager] Playing sound:", soundType)
        _platformPlaySound(soundType)
    }
    
    function vibrate(pattern) {
        if (!vibrationEnabled) return
        console.log("[AudioManager] Vibrating:", pattern)
        _platformVibrate(pattern)
    }
    
    function _platformSetVolume(value) {
        if (Platform.hasPulseAudio) {
            console.log("[AudioManager] PulseAudio pactl set-sink-volume")
        } else if (Platform.isMacOS) {
            console.log("[AudioManager] macOS osascript set volume")
        }
    }
    
    function _platformSetMuted(mute) {
        if (Platform.hasPulseAudio) {
            console.log("[AudioManager] PulseAudio pactl set-sink-mute", mute)
        } else if (Platform.isMacOS) {
            console.log("[AudioManager] macOS osascript set volume", mute ? 0 : volume)
        }
    }
    
    function _platformSetAudioProfile(profile) {
        if (Platform.isLinux) {
            console.log("[AudioManager] Setting PulseAudio profile:", profile)
        } else if (Platform.isAndroid) {
            console.log("[AudioManager] Android AudioManager.setRingerMode")
        }
    }
    
    function _platformSetVibration(enabled) {
        if (Platform.isLinux) {
            console.log("[AudioManager] Vibration control via input device")
        } else if (Platform.isAndroid) {
            console.log("[AudioManager] Android Vibrator service")
        }
    }
    
    function _platformSetDoNotDisturb(enabled) {
        if (Platform.isLinux) {
            console.log("[AudioManager] DND via notification daemon")
        } else if (Platform.isMacOS) {
            console.log("[AudioManager] macOS Do Not Disturb")
        }
    }
    
    function _platformSetStreamVolume(stream, value) {
        if (Platform.hasPulseAudio) {
            console.log("[AudioManager] PulseAudio set stream volume:", stream, value)
        }
    }
    
    function _platformPlaySound(soundType) {
        if (Platform.isLinux) {
            console.log("[AudioManager] Playing sound via canberra-gtk-play or paplay")
        }
    }
    
    function _platformVibrate(pattern) {
        if (Platform.isLinux) {
            console.log("[AudioManager] Vibrate pattern:", pattern)
        }
    }
    
    Component.onCompleted: {
        console.log("[AudioManager] Initialized")
        console.log("[AudioManager] PulseAudio available:", Platform.hasPulseAudio)
        console.log("[AudioManager] Current profile:", audioProfile)
    }
}

