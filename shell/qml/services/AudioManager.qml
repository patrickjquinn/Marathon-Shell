pragma Singleton
import MarathonOS.Shell
import QtQuick

QtObject {
    id: audioManager

    // Runtime master volume comes from C++ backend (wpctl/pulseaudio).
    property real volume: typeof AudioManagerCpp !== 'undefined' ? AudioManagerCpp.volume : SettingsManagerCpp.systemVolume
    property bool muted: typeof AudioManagerCpp !== 'undefined' ? AudioManagerCpp.muted : false
    // Persisted policy lives in SettingsManager (C++), applied by AudioPolicyController (C++).
    property bool vibrationEnabled: SettingsManagerCpp.vibrationEnabled
    property bool dndEnabled: SettingsManagerCpp.dndEnabled
    property string audioProfile: SettingsManagerCpp.audioProfile
    readonly property var availableProfiles: ["silent", "vibrate", "normal", "loud"]
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

    function setRingtone(path) {
        SettingsManagerCpp.ringtone = path;
    }

    function setNotificationSound(path) {
        SettingsManagerCpp.notificationSound = path;
    }

    function setAlarmSound(path) {
        SettingsManagerCpp.alarmSound = path;
    }

    function setVolume(value) {
        var clamped = Math.max(0, Math.min(1, value));
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.setMasterVolume(clamped);
    }

    function setMuted(mute) {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.setMuted(mute);
    }

    function toggleMute() {
        setMuted(!muted);
    }

    function setAudioProfile(profile) {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.setAudioProfile(profile);
    }

    function setDoNotDisturb(enabled) {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.setDoNotDisturb(enabled);
    }

    function playRingtone() {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.playRingtone();
    }

    function stopRingtone() {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.stopRingtone();
    }

    function playNotificationSound() {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.playNotificationSound();
    }

    function playAlarmSound() {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.playAlarmSound();
    }

    function stopAlarmSound() {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.stopAlarmSound();
    }

    // Preview functions for settings app - use dedicated preview player
    function previewRingtone(soundPath) {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.previewSound(soundPath);
    }

    function previewNotificationSound(soundPath) {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.previewSound(soundPath);
    }

    function previewAlarmSound(soundPath) {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.previewSound(soundPath);
    }

    function vibrate(pattern) {
        if (typeof AudioPolicyControllerCpp !== 'undefined')
            AudioPolicyControllerCpp.vibratePattern(pattern);
    }
}
