# Roadmap tracker

Work from the 2026-10-17 State of the Project review, tracked across the agent pool.
Status: `todo` · `active` · `review` (merged, awaiting device test) · `done` (merged, verified) · `blocked`.
Finding numbers refer to the review's Findings table.

| ID | Item | Findings | Wave | Status | Notes |
|---|---|---|---|---|---|
| R01 | CI on pull requests (build + ctest + clippy), actions pinned by SHA | 1 | 0 | review | 09037abc; first GitHub run on the next PR |
| R02 | PR template asking for evidence | 1 | 0 | review | 8de09d85 |
| R03 | Music library proxy in the runner | 5 | – | done | already on main |
| R04 | CONTEXT.md, README, device/image/packaging docs, patch index, screenshots | 6, 15 | – | done | 950e5417 |
| R05 | DAV secrets in the Secret Service | 4 | – | done | 6c944f37 |
| R06 | Debug-app auto-launch opt-in; inverted log guard; dead WAYLAND_DISPLAY | 16, 17, 18 | – | done | dfd3fcc7, 94919ea9 |
| R07 | Stale comments | 20 | – | done | 10f3c7e3 |
| R08 | Hub notification tap opens the app | new | 1 | review | + tap-time resolution 10fa7a98; re-verify in r456 |
| R09 | Audio on PipeWire/WirePlumber (no PulseAudio API, no wpctl/pactl subprocesses) | 13 | 1 | review | playback + BT volume verified r461; call routing needs a modem device |
| R10 | App signing: whole-package Ed25519/minisign, required by default, verified before parsing; generated permission disclosures; hold permission-widening updates | 2 | 1 | review | minisign whole-package signing, disclosures, held widening updates; device test in r456 |
| R11 | Signed OTA: A/B or snapshot update, health check, automatic rollback, metered/battery gating | 3 | 1 | review | systemd-sysupdate A/B behind MARATHON_IMAGE_LAYOUT=ab; QEMU validation pending (needs ~30 GB, signing key, feed host) |
| R12 | Sandbox: security-context-v1 for sandboxed clients, marathon-sandbox defaults, WebEngine sandbox, no setcap in setup | 7, 8, 9 | 1 | review | security-context socket verified r457 |
| R13 | App manifest JSON schema + `marathon-dev lint` | 2 | 2 | review | schemas/marathon-app-manifest-v1 + marathon-dev lint; all apps pass |
| R14 | Device manifests (devices/<vendor>/<codename>) generating device-profile.conf; PinePhone build wrapper + flash script | 15 | 2 | review | devices/*/device.toml + socs/; generated device-profile.conf; PinePhone build/flash scripts |
| R15 | Design tokens from one source; lint hex/durations; reduceBlur | 10 | 2 | todo | |
| R16 | Input + presentation context separate from width; MSAA defaults reconciled | 12 | 2 | todo | |
| R17 | Background agents (systemd timers, RTC wake) + modem quiesce/resume around suspend | 9 | 2 | review | marathon-background generator + RTC wake arming; modem-sleep hook; device test in r456 |
| R18 | Live Activities: typed app state → Frames, NowBar, lock screen with redaction | 9 | 2 | todo | |
| R19 | Hygiene: Word Fling/predictive spacing dead settings, root pam.d/udev/systemd reconcile, legacy components/ui | 19, new | 2 | review | merged (to c2f00e11); PIN unlock + backlight to verify on device (PAM/udev moved) |
| R20 | i18n (qsTr + Qt translations) and Accessible annotations | 11 | 3 | todo | |
| R21 | App fixture mode + screenshot conformance on QEMU | 1 | 3 | todo | |
| R22 | Process kit: changelog fragments, test-reachability check | 1 | 3 | done | git-cliff release notes + PR subject check; Lint_TestReachability (8e0fefb8..d39a59ab) |
| R23 | VoLTE evaluation (imsd, separate GPL-3 process) | 14 | 3 | done | docs/research/VOLTE.md: modem-side IMS; Phase 0 check script needs a modem device |
| R24 | Lint clean: clang-tidy/clazy/clang-format, qmllint shell + apps, lint infra for Marathon.Platform | – | 3 | todo | partial lint-infra patch saved |
| R26 | Keyboard edits reach apps: autocorrect replace, backspace, double-space period; tests on the real keyboard QML | new | 2 | done | found by R19; verified r457, r461 |
| R27 | Audit possibly dead settings (dateFormat, statusBarClockPosition, showFrequentApps, appSortOrder, …) | new | 3 | todo | found by R19 |
| R28 | Permission integrity: app cannot rewrite its own manifest to gain grants; one permission vocabulary; no silent denials | new | 2 | review | merged (ec5d7e45..01b8c7eb); verified r463: stored system grant ignored, prompt asks undecided permissions, Terminal protected; crafted-manifest sideload + uninstall lifecycle not yet run on device |
| R29 | Gestures: short pull from the pill opens QS; Peek edge strip skips the back indicator | user | – | review | 1cbed1b4, e93992e8; device test in r456 |
| R30 | OEM test-app findings (calls, permissions, lock-after-decline, …) | OEM run | – | active | docs/testing/OEM_TEST_HACKBERRYPI_2026-10-17.md; R31–R36 fixing; lock/decline/SMS/alarm verified r459 |
| R31 | Notification actions, custom icons, banner queue | OEM F8,F10,F11 | – | done | verified on device r460 |
| R32 | Lock after decline/SMS/alarm; declined ≠ missed | OEM F5,F6,F27,F28 | – | done | verified on device r459 |
| R33 | Keyboard: autocorrect keeps case; no capital after every space on device | OEM F14,F15 | – | done | verified on device r461 |
| R34 | Alarms wake the device (root-armed RTC timer); WakeManager | OEM | – | done | verified r463: wake timer armed per alarm, a ringing alarm lit a blanked screen at 14:31:01; idle hold covered by host test (device timeout is Never) |
| R35 | Display/power: one screen-state owner (frozen-touch bug), power-profiles-daemon, auto-brightness, backlight steps | OEM F18–F21 | – | review | verified r463: F19, F20, F21; F18 needs an image with tuned-ppd |
| R36 | marathon-audiod volume/mute on Bluetooth sinks; profile state | OEM F25,F26 | – | done | verified on device r461 |
| R37 | OEM minor findings: one-off alarm count, torch availability, Location.active, QS slider rounding + OSD, call-state wording, hardware cursor spam | OEM F9,F23,F24,F29,F31–F33 | – | done | verified r463 |
| R38 | Alarm/ringtone audible at their own volume (WirePlumber media roles); refused values say so; terminal hold keys; prompt icons/footer | OEM F34–F37 | – | review | merged (a96c35c0..5ac42e47); device test on the A/B image |
| R39 | OTA experience like iOS/Android: update notifications, automatic overnight install, "Finishing update…" splash, "Updated to" notice | user | – | done | verified on device: background download, restart notification, "Updated to", rollback notice |
| R40 | A/B OTA on the Raspberry Pi 5 / HackberryPi CM5: GPT slots, tryboot, marathon-health commit | user | – | done | validated on the HackberryPi 2026-10-17: flash, update + commit, bad update falls back (docs/OTA.md) |
| R41 | App install/uninstall through the shell (sandboxes see installs read-only since R28); no Uninstall for built-in apps | OEM F45 | – | done | c051ca4c..823ddb3c; verified on the HackberryPi via OTA 26101707 |
| R43 | Mobile data retry storm when the modem cannot be enabled: NetworkManager re-dials the shell's "Mobile data" gsm profile hundreds of times a second | JP2601 bring-up | – | done | 2026-11-26 on the JP2601: ModemManager failed every enable within ~6 ms (+CME ERROR: 100 on ATZ, fixed in modemmanager-mtk-ccci 0114). NM's modem-broadband device (ttyC0) then cycled prepare → disconnected (user-requested) many times a second, and MM logged a simple-connect/enable/failed triple every ~10 ms, burning CPU and power until NM WwanEnabled was set false. The profile has no autoconnect-retries (modem.rs set_data removes it), and NM files each fall back to disabled as a user-requested disconnect, which never consumes an autoconnect retry, so no retry cap would stop it either. Want: a backoff (or a retry cap that survives modem state changes) whenever enabling or connecting fails, and a visible "mobile data unavailable" state. Root cause in NetworkManager 1.58 (src/core/devices/wwan/nm-device-modem.c, modem_state_cb): when the modem drops from enabling back to disabled while NM itself is activating it, NM takes it for an external change and moves the device to DISCONNECTED with reason USER_REQUESTED instead of FAILED, so no retry is spent. NM has no conf knob for this, and the dispatcher never fires for an activation that never came up, so there is no conf- or dispatcher-level guard. The upstreamable fix is in that function: when old_state was ENABLING during an activation, fail the device (NM_DEVICE_STATE_REASON_MODEM_INIT_FAILED) so autoconnect-retries apply. 2026-11-27: shell fix 03b186491 + 2c1ee68fe + cd8a0b376 (feat/form-factor, data_backoff.rs). After a failed activation (device state 40-90 to 20/30/120) the shell sets the NM device's runtime Autoconnect false (BLOCKED_USER: it survives the shell's own ActivateConnection and leaves the saved toggle alone), dials again after 10/20/40/80/160 s, then stops after the sixth failure and shows Modem.dataFailed ("Can't connect" on the quick settings tile, "Couldn't connect. Tap to try again." in Settings). A connection, the switch or WWAN back on resets it. Also, modemmanager-mtk-ccci 0115 lets the shell's APN-less profile connect on the JP2601's NR17 modem. Verified on the JP2601 (r11, SHELL-UX9): WWAN on makes NM bring the APN-less profile up at once; with a bogus APN NM got one extra try in before the block took, then the shell retried at +20/+40/+80/+160 s and stopped after the sixth failure (21 PDN activations in 5 min, MM retrying each once), showing the tile and Settings text; tapping the Settings switch reconnected at once and set autoconnect back to true. The enable-failure storm itself was not reproduced (ATZ is fixed in 0114); it ends in the same activating-to-disconnected transition the shell now counts |
| R25 | Integration build, device test on HackberryPi, OTA test on QEMU | – | 4 | todo | |
