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
| R08 | Hub notification tap opens the app | new | 1 | review | 646141ad; device test in r455 |
| R09 | Audio on PipeWire/WirePlumber (no PulseAudio API, no wpctl/pactl subprocesses) | 13 | 1 | active | |
| R10 | App signing: whole-package Ed25519/minisign, required by default, verified before parsing; generated permission disclosures; hold permission-widening updates | 2 | 1 | active | reef-licence prior art |
| R11 | Signed OTA: A/B or snapshot update, health check, automatic rollback, metered/battery gating | 3 | 1 | active | systemd-sysupdate + boot assessment |
| R12 | Sandbox: security-context-v1 for sandboxed clients, marathon-sandbox defaults, WebEngine sandbox, no setcap in setup | 7, 8, 9 | 1 | active | |
| R13 | App manifest JSON schema + `marathon-dev lint` | 2 | 2 | active | Keel Actions schema prior art |
| R14 | Device manifests (devices/<vendor>/<codename>) generating device-profile.conf; PinePhone build wrapper + flash script | 15 | 2 | active | |
| R15 | Design tokens from one source; lint hex/durations; reduceBlur | 10 | 2 | todo | |
| R16 | Input + presentation context separate from width; MSAA defaults reconciled | 12 | 2 | todo | |
| R17 | Background agents (systemd timers, RTC wake) + modem quiesce/resume around suspend | 9 | 2 | active | |
| R18 | Live Activities: typed app state → Frames, NowBar, lock screen with redaction | 9 | 2 | todo | |
| R19 | Hygiene: Word Fling/predictive spacing dead settings, root pam.d/udev/systemd reconcile, legacy components/ui | 19, new | 2 | active | |
| R20 | i18n (qsTr + Qt translations) and Accessible annotations | 11 | 3 | todo | |
| R21 | App fixture mode + screenshot conformance on QEMU | 1 | 3 | todo | |
| R22 | Process kit: changelog fragments, test-reachability check | 1 | 3 | active | |
| R23 | VoLTE evaluation (imsd, separate GPL-3 process) | 14 | 3 | active | needs a modem device |
| R24 | Lint clean: clang-tidy/clazy/clang-format, qmllint shell + apps, lint infra for Marathon.Platform | – | 3 | todo | partial lint-infra patch saved |
| R25 | Integration build, device test on HackberryPi, OTA test on QEMU | – | 4 | todo | |
