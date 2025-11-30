pragma Singleton
import QtQuick
import QtMultimedia 6.0
import MarathonOS.Shell

QtObject {
    id: audioManager
    // Volume
    property real volume: 0.6  // Managed by binding below
    property real minVolume: 0.0
    property real maxVolume: 1.0

    // Audio device detection
    property var audioDevices: MediaDevices

    property bool muted: false
    property bool vibrationEnabled: true
    property bool dndEnabled: false

    property string audioProfile: "normal"
    property var availableProfiles: ["silent", "vibrate", "normal", "loud"]

    property string audioOutput: "speaker"
    property var availableOutputs: ["speaker", "headphones", "bluetooth", "usb"]

    property bool headphonesConnected: false
    property bool bluetoothAudioConnected: false

    property real mediaVolume: SettingsManagerCpp.mediaVolume
    property real ringtoneVolume: SettingsManagerCpp.ringtoneVolume
    property real alarmVolume: SettingsManagerCpp.alarmVolume
    property real notificationVolume: SettingsManagerCpp.notificationVolume
    property real systemVolume: SettingsManagerCpp.systemVolume

    // Sound file properties
    property string currentRingtone: SettingsManagerCpp.ringtone
    property string currentNotificationSound: SettingsManagerCpp.notificationSound
    property string currentAlarmSound: SettingsManagerCpp.alarmSound

    // Available sounds (computed once)
    readonly property var availableRingtones: SettingsManagerCpp.availableRingtones()
    readonly property var availableNotificationSounds: SettingsManagerCpp.availableNotificationSounds()
    readonly property var availableAlarmSounds: SettingsManagerCpp.availableAlarmSounds()

    // Monitor AudioManagerCpp for hardware key volume changes
    property Connections volumeMonitor: Connections {
        target: typeof AudioManagerCpp !== 'undefined' ? AudioManagerCpp : null

        function onVolumeChanged() {
            if (AudioManagerCpp && AudioManagerCpp.available) {
                console.log("[AudioManager] Volume changed externally:", (AudioManagerCpp.volume * 100).toFixed(0) + "%");
                audioManager.volume = AudioManagerCpp.volume;
            }
        }

        function onMutedChanged() {
            if (AudioManagerCpp && AudioManagerCpp.available) {
                console.log("[AudioManager] Mute changed externally:", AudioManagerCpp.muted);
                audioManager.muted = AudioManagerCpp.muted;
            }
        }
    }

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
        // Only set C++ property - binding will update currentRingtone automatically
        SettingsManagerCpp.ringtone = path;
    }

    function setNotificationSound(path) {
        // Only set C++ property - binding will update currentNotificationSound automatically
        SettingsManagerCpp.notificationSound = path;
    }

    function setAlarmSound(path) {
        // Only set C++ property - binding will update currentAlarmSound automatically
        SettingsManagerCpp.alarmSound = path;
    }

    function setVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value));
        console.log("[AudioManager] Setting volume:", clamped);
        volume = clamped;
        volumeSet(clamped);
        _platformSetVolume(clamped);
    }

    function increaseVolume(step) {
        setVolume(volume + (step || 0.1));
    }

    function decreaseVolume(step) {
        setVolume(volume - (step || 0.1));
    }

    function setMuted(mute) {
        console.log("[AudioManager] Muted:", mute);
        muted = mute;
        muteToggled(mute);
        _platformSetMuted(mute);
    }

    function toggleMute() {
        setMuted(!muted);
    }

    function setAudioProfile(profile) {
        if (availableProfiles.indexOf(profile) === -1) {
            console.warn("[AudioManager] Invalid audio profile:", profile);
            return;
        }

        console.log("[AudioManager] Audio profile:", profile);
        audioProfile = profile;

        switch (profile) {
        case "silent":
            setMuted(true);
            vibrationEnabled = false;
            break;
        case "vibrate":
            setMuted(true);
            vibrationEnabled = true;
            break;
        case "normal":
            setMuted(false);
            vibrationEnabled = true;
            break;
        case "loud":
            setMuted(false);
            vibrationEnabled = true;
            setVolume(0.9);
            break;
        }

        profileChanged(profile);
        _platformSetAudioProfile(profile);
    }

    function setVibration(enabled) {
        console.log("[AudioManager] Vibration:", enabled);
        vibrationEnabled = enabled;
        _platformSetVibration(enabled);
    }

    function setDoNotDisturb(enabled) {
        console.log("[AudioManager] Do Not Disturb:", enabled);
        dndEnabled = enabled;
        _platformSetDoNotDisturb(enabled);
    }

    function setMediaVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value));
        mediaVolume = clamped;
        SettingsManagerCpp.mediaVolume = clamped;
        _platformSetStreamVolume("media", clamped);
    }

    function setRingtoneVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value));
        ringtoneVolume = clamped;
        SettingsManagerCpp.ringtoneVolume = clamped;
        _platformSetStreamVolume("ringtone", clamped);
    }

    function setAlarmVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value));
        alarmVolume = clamped;
        SettingsManagerCpp.alarmVolume = clamped;
        _platformSetStreamVolume("alarm", clamped);
    }

    function setNotificationVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value));
        notificationVolume = clamped;
        SettingsManagerCpp.notificationVolume = clamped;
        _platformSetStreamVolume("notification", clamped);
    }

    function setSystemVolume(value) {
        var clamped = Math.max(minVolume, Math.min(maxVolume, value));
        systemVolume = clamped;
        SettingsManagerCpp.systemVolume = clamped;
        _platformSetStreamVolume("system", clamped);
    }

    function playSound(soundType) {
        console.log("[AudioManager] Playing sound:", soundType);
        _platformPlaySound(soundType);
    }

    function playRingtone() {
        if (dndEnabled) {
            Logger.info("AudioManager", "Ringtone suppressed (DND enabled)");
            return;
        }

        Logger.info("AudioManager", "Playing ringtone: " + currentRingtone);

        // Check if media is already loaded and ready
        if (ringtonePlayer.mediaStatus === MediaPlayer.LoadedMedia && ringtonePlayer.source.toString() === currentRingtone.toString()) {
            // Already loaded, play immediately
            ringtonePlayer.loops = MediaPlayer.Infinite;
            ringtonePlayer.play();
        } else if (ringtonePlayer.mediaStatus === MediaPlayer.EndOfMedia && ringtonePlayer.source.toString() === currentRingtone.toString()) {
            // Media finished (edge case after stop) - stop and replay
            ringtonePlayer.stop();
            ringtonePlayer.loops = MediaPlayer.Infinite;
            ringtonePlayer.play();
        } else if (ringtonePlayer.source.toString() !== currentRingtone.toString()) {
            // Source changed - reload
            ringtonePlayer.stop();
            ringtonePlayer.source = currentRingtone;
            ringtonePlayPending = true;
        } else {
            // Source is set but not loaded yet - wait
            ringtonePlayPending = true;
        }
    }

    property bool ringtonePlayPending: false

    function stopRingtone() {
        Logger.info("AudioManager", "Stopping ringtone");
        ringtonePlayPending = false;
        ringtonePlayer.stop();
    }

    function playNotificationSound() {
        if (dndEnabled) {
            Logger.info("AudioManager", "Notification sound suppressed (DND enabled)");
            return;
        }

        Logger.info("AudioManager", "Playing notification sound: " + currentNotificationSound);
        console.log("[AudioManager] Current player source:", notificationPlayer.source);
        console.log("[AudioManager] Current setting:", currentNotificationSound);
        console.log("[AudioManager] Sources match:", notificationPlayer.source.toString() === currentNotificationSound.toString());
        console.log("[AudioManager] Current player state:", notificationPlayer.playbackState);
        console.log("[AudioManager] Current player media status:", notificationPlayer.mediaStatus);

        // Check if media is already loaded and ready
        if (notificationPlayer.mediaStatus === MediaPlayer.LoadedMedia && notificationPlayer.source.toString() === currentNotificationSound.toString()) {
            // Already loaded, play immediately
            console.log("[AudioManager] Media already loaded - playing now");
            notificationPlayer.play();
            console.log("[AudioManager] play() called - state:", notificationPlayer.playbackState);
        } else if (notificationPlayer.mediaStatus === MediaPlayer.EndOfMedia && notificationPlayer.source.toString() === currentNotificationSound.toString()) {
            // Media finished playing but same source - stop and replay
            console.log("[AudioManager] Media at EndOfMedia - resetting and replaying");
            notificationPlayer.stop();
            notificationPlayer.play();
        } else if (notificationPlayer.source.toString() !== currentNotificationSound.toString()) {
            // Source changed - reload
            console.log("[AudioManager] Source changed - reloading");
            notificationPlayer.stop();
            notificationPlayer.source = currentNotificationSound;
            notificationPlayPending = true;
        } else {
            // Source is set but not loaded yet - wait
            console.log("[AudioManager] Waiting for media to load...");
            notificationPlayPending = true;
        }
    }

    property bool notificationPlayPending: false

    function playAlarmSound() {
        Logger.info("AudioManager", "Playing alarm sound: " + currentAlarmSound);

        // Check if media is already loaded and ready
        if (alarmPlayer.mediaStatus === MediaPlayer.LoadedMedia && alarmPlayer.source.toString() === currentAlarmSound.toString()) {
            // Already loaded, play immediately
            alarmPlayer.loops = MediaPlayer.Infinite;
            alarmPlayer.play();
        } else if (alarmPlayer.mediaStatus === MediaPlayer.EndOfMedia && alarmPlayer.source.toString() === currentAlarmSound.toString()) {
            // Media finished (edge case after stop) - stop and replay
            alarmPlayer.stop();
            alarmPlayer.loops = MediaPlayer.Infinite;
            alarmPlayer.play();
        } else if (alarmPlayer.source.toString() !== currentAlarmSound.toString()) {
            // Source changed - reload
            alarmPlayer.stop();
            alarmPlayer.source = currentAlarmSound;
            alarmPlayPending = true;
        } else {
            // Source is set but not loaded yet - wait
            alarmPlayPending = true;
        }
    }

    property bool alarmPlayPending: false

    function stopAlarmSound() {
        Logger.info("AudioManager", "Stopping alarm sound");
        alarmPlayPending = false;
        alarmPlayer.stop();
    }

    // Dedicated preview player - separate from main audio system to avoid conflicts
    property var previewPlayer: MediaPlayer {
        id: previewAudio
        audioOutput: AudioOutput {
            volume: 0.7  // Fixed preview volume
            muted: false
        }
        loops: MediaPlayer.Once

        onErrorOccurred: (error, errorString) => {
            console.error("[AudioManager] Preview player error:", error, errorString);
        }
    }

    // Preview functions for settings app - use dedicated preview player
    function previewRingtone(soundPath) {
        Logger.info("AudioManager", "Previewing ringtone: " + soundPath);
        previewPlayer.stop();
        previewPlayer.source = soundPath;
        // Use Qt.callLater to ensure source is set before playing
        Qt.callLater(function () {
            previewPlayer.play();
        });
    }

    function previewNotificationSound(soundPath) {
        Logger.info("AudioManager", "Previewing notification: " + soundPath);
        previewPlayer.stop();
        previewPlayer.source = soundPath;
        // Use Qt.callLater to ensure source is set before playing
        Qt.callLater(function () {
            previewPlayer.play();
        });
    }

    function previewAlarmSound(soundPath) {
        Logger.info("AudioManager", "Previewing alarm: " + soundPath);
        previewPlayer.stop();
        previewPlayer.source = soundPath;
        // Use Qt.callLater to ensure source is set before playing
        Qt.callLater(function () {
            previewPlayer.play();
        });
    }

    function vibrate(pattern) {
        if (!vibrationEnabled)
            return;
        console.log("[AudioManager] Vibrating:", pattern);
        _platformVibrate(pattern);
    }

    // Audio players for ringtones, notifications, and alarms (Qt6 MediaPlayer + AudioOutput)
    property var ringtonePlayer: MediaPlayer {
        id: ringtoneAudio
        audioOutput: AudioOutput {
            // Don't set device - let GStreamer auto-detect via pulsesink
            volume: audioManager.ringtoneVolume

            Component.onCompleted: {
                console.log("[AudioManager] Ringtone AudioOutput - letting GStreamer auto-detect device");
            }
        }
        loops: MediaPlayer.Infinite

        onMediaStatusChanged: {
            console.log("[AudioManager] Ringtone media status:", mediaStatus);
            if (mediaStatus === MediaPlayer.LoadedMedia && audioManager.ringtonePlayPending) {
                audioManager.ringtonePlayPending = false;
                loops = MediaPlayer.Infinite;
                play();
            }
        }

        onErrorOccurred: (error, errorString) => {
            console.error("[AudioManager] Ringtone player error:", error, errorString);
            audioManager.ringtonePlayPending = false;
        }
    }

    property var notificationPlayer: MediaPlayer {
        id: notificationAudio
        audioOutput: AudioOutput {
            id: notificationOutput
            volume: audioManager.notificationVolume
            muted: false

            Component.onCompleted: {
                console.log("[AudioManager] Notification AudioOutput - letting GStreamer auto-detect device");
                console.log("[AudioManager] Notification AudioOutput volume:", notificationOutput.volume);
                console.log("[AudioManager] Notification AudioOutput muted:", notificationOutput.muted);
            }

            onVolumeChanged: {
                console.log("[AudioManager] Notification AudioOutput volume changed to:", notificationOutput.volume);
            }

            onMutedChanged: {
                console.log("[AudioManager] Notification AudioOutput muted changed to:", notificationOutput.muted);
            }
        }
        loops: MediaPlayer.Once

        onMediaStatusChanged: {
            console.log("[AudioManager] Notification media status:", mediaStatus);
            if (mediaStatus === MediaPlayer.LoadedMedia && audioManager.notificationPlayPending) {
                audioManager.notificationPlayPending = false;
                play();
            }
        }

        onErrorOccurred: (error, errorString) => {
            console.error("[AudioManager] Notification player error:", error, errorString);
            audioManager.notificationPlayPending = false;
        }

        onPlaybackStateChanged: {
            console.log("[AudioManager] Notification playback state:", playbackState, "- source:", source);
            if (playbackState === MediaPlayer.PlayingState) {
                console.log("[AudioManager] PLAYING - AudioOutput volume:", audioOutput.volume, "muted:", audioOutput.muted);
            }
        }
    }

    property var alarmPlayer: MediaPlayer {
        id: alarmAudio
        audioOutput: AudioOutput {
            // Don't set device - let GStreamer auto-detect via pulsesink
            volume: audioManager.alarmVolume

            Component.onCompleted: {
                console.log("[AudioManager] Alarm AudioOutput - letting GStreamer auto-detect device");
            }
        }
        loops: MediaPlayer.Infinite

        onMediaStatusChanged: {
            console.log("[AudioManager] Alarm media status:", mediaStatus);
            if (mediaStatus === MediaPlayer.LoadedMedia && audioManager.alarmPlayPending) {
                audioManager.alarmPlayPending = false;
                loops = MediaPlayer.Infinite;
                play();
            }
        }

        onErrorOccurred: (error, errorString) => {
            console.error("[AudioManager] Alarm player error:", error, errorString);
            audioManager.alarmPlayPending = false;
        }
    }

    function _platformSetVolume(value) {
        // Use existing AudioManagerCpp backend
        if (typeof AudioManagerCpp !== 'undefined' && AudioManagerCpp.available) {
            AudioManagerCpp.setVolume(value);
        } else {
            console.log("[AudioManager] AudioManagerCpp not available, volume set to:", (value * 100).toFixed(0) + "%");
        }
    }

    function _platformSetMuted(mute) {
        if (Platform.hasPulseAudio) {
            // Use pactl to mute/unmute system
            Qt.callLater(function () {
                Platform.execute("pactl", ["set-sink-mute", "@DEFAULT_SINK@", mute ? "1" : "0"]);
            });
        } else if (Platform.isMacOS) {
            console.log("[AudioManager] macOS osascript set volume", mute ? 0 : volume);
        }
    }

    function _platformSetAudioProfile(profile) {
        if (Platform.isLinux) {
            console.log("[AudioManager] Setting PulseAudio profile:", profile);
        } else if (Platform.isAndroid) {
            console.log("[AudioManager] Android AudioManager.setRingerMode");
        }
    }

    function _platformSetVibration(enabled) {
        if (Platform.isLinux) {
            console.log("[AudioManager] Vibration control via input device");
        } else if (Platform.isAndroid) {
            console.log("[AudioManager] Android Vibrator service");
        }
    }

    function _platformSetDoNotDisturb(enabled) {
        if (Platform.isLinux) {
            console.log("[AudioManager] DND via notification daemon");
        } else if (Platform.isMacOS) {
            console.log("[AudioManager] macOS Do Not Disturb");
        }
    }

    function _platformSetStreamVolume(stream, value) {
        if (Platform.hasPulseAudio) {
            // Set volume for specific stream types
            var percentage = Math.round(value * 100);
            Qt.callLater(function () {
                Platform.execute("pactl", ["set-sink-volume", "@DEFAULT_SINK@", percentage + "%"]);
            });
        }
    }

    function _platformPlaySound(soundType) {
        if (Platform.isLinux) {
            console.log("[AudioManager] Playing sound via canberra-gtk-play or paplay");
        }
    }

    function _platformVibrate(pattern) {
        if (Platform.isLinux) {
            console.log("[AudioManager] Vibrate pattern:", pattern);
        }
    }

    Component.onCompleted: {
        console.log("[AudioManager] Initialized");
        console.log("[AudioManager] PulseAudio available:", Platform.hasPulseAudio);
        console.log("[AudioManager] Current profile:", audioProfile);

        // Log available audio devices (Qt MediaDevices API may not work with all backends)
        var outputs = audioDevices.audioOutputs;
        if (outputs && outputs.length !== undefined) {
            console.log("[AudioManager] Available audio outputs:", outputs.length);
            for (var i = 0; i < outputs.length; i++) {
                console.log("[AudioManager]  - Device", i + ":", outputs[i].description, "(id:", outputs[i].id + ")");
            }
        } else {
            console.log("[AudioManager] Qt MediaDevices API unavailable - using GStreamer auto-detection");
        }

        var defaultOutput = audioDevices.defaultAudioOutput;
        if (defaultOutput) {
            console.log("[AudioManager] Default audio output:", defaultOutput.description, "(id:", defaultOutput.id + ")");
        } else {
            console.log("[AudioManager] No Qt default audio output - GStreamer will auto-select device");
        }

        // Preload media sources to avoid blocking on first play
        console.log("[AudioManager] Preloading media sources...");
        ringtonePlayer.source = currentRingtone;
        notificationPlayer.source = currentNotificationSound;
        alarmPlayer.source = currentAlarmSound;
        previewPlayer.source = "";  // Start empty
    }
}
