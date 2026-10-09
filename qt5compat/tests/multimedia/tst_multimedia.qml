// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 QtMultimedia API under `import QtMultimedia 5.x`, as nayttamo and
// hafenschau use it: MediaPlayer with Qt 5 enums and signals, VideoOutput
// pointed at the player, Audio, SoundEffect. Needs Qt 6 Multimedia with a
// working backend (see README.md); no media is played.
import QtQuick 2.0
import QtTest 1.0
import QtMultimedia 5.6

Item {
    width: 100; height: 100

    MediaPlayer {
        id: player
        autoPlay: false
        volume: 0.5
    }
    Audio { id: audio }
    VideoOutput {
        id: out
        anchors.fill: parent
        source: player
        fillMode: VideoOutput.PreserveAspectCrop
        MouseArea { id: area; anchors.fill: parent }
    }
    SoundEffect { id: effect; loops: SoundEffect.Infinite; category: "game" }

    SignalSpy { id: errorSpy; target: player; signalName: "error" }

    TestCase {
        name: "QtMultimedia5"

        function test_enums() {
            compare(MediaPlayer.StoppedState, 0)
            compare(MediaPlayer.PlayingState, 1)
            compare(MediaPlayer.PausedState, 2)
            compare(MediaPlayer.UnknownStatus, 0)
            compare(MediaPlayer.NoMedia, 1)
            compare(MediaPlayer.Loading, 2)
            compare(MediaPlayer.Buffering, 5)
            compare(MediaPlayer.InvalidMedia, 8)
            player.loops = MediaPlayer.Infinite
            compare(player.__player.loops, -1)
            player.loops = -1
            compare(player.__player.loops, -1)
            player.loops = 2
            compare(player.__player.loops, 2)
            player.loops = 1
            compare(MediaPlayer.AccessDenied, 4)
            compare(Audio.PlayingState, 1)
            compare(VideoOutput.PreserveAspectFit, 1)
        }
        function test_initial_state() {
            compare(player.playbackState, MediaPlayer.StoppedState)
            compare(player.status, MediaPlayer.NoMedia)
            compare(player.position, 0)
            compare(player.volume, 0.5)
            compare(player.__player.audioOutput.volume, 0.5)
            player.muted = true
            verify(player.__player.audioOutput.muted)
            compare(audio.playbackState, Audio.StoppedState)
        }
        function test_video_output_attached() {
            compare(player.__player.videoOutput, out.__output)
            compare(out.fillMode, VideoOutput.PreserveAspectCrop)
            compare(out.__output.fillMode, VideoOutput.PreserveAspectCrop)
            compare(area.parent, out)
            out.source = null
            compare(player.__player.videoOutput, null)
            out.source = player
            compare(player.__player.videoOutput, out.__output)
        }
        function test_invalid_source_reports_error() {
            player.source = "file:///nonexistent/keel-qt5compat-test.mp4"
            player.play()
            tryVerify(function () {
                return errorSpy.count > 0 || player.status === MediaPlayer.InvalidMedia
            }, 5000)
            player.stop()
            compare(player.playbackState, MediaPlayer.StoppedState)
        }
        function test_sound_effect() {
            compare(effect.loops, SoundEffect.Infinite)
            compare(effect.category, "game")
            verify(!effect.playing)
        }
    }
}
