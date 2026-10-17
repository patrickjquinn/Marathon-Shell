# Background work and suspend

How apps and system services run periodic work without keeping a process
alive, how that work reaches a device that is dozing or suspended, and how
the modem is looked after across a suspend.

## How Marathon sleeps

Marathon's daily sleep is **Doze** (`PowerPolicyController`): screen off,
background apps frozen, kernel, Wi-Fi and modem running. Nothing suspends
the system automatically. A real suspend happens only on a critical battery
(when UPower's action is Suspend), through `org.marathonos.Shell.Power1.Suspend`,
or from `systemctl suspend`.

So background work has two cases:

- **Awake or dozing**: user timers fire as normal. A frozen app is thawed for
  the call (below) and frozen again after its grace period.
- **Suspended**: only a wake-capable timer brings the device back, and only
  tasks that ask for it (`"wake": true`) arm one.

## Declaring tasks: `backgroundTasks`

An app declares tasks in its `manifest.json`. Each task names one of the app's
Keel Actions (its `keel-actions.json`, installed by `install_keel_actions`);
running the task is invoking that action.

```json
"backgroundTasks": [
  {
    "id": "sync",
    "action": "mail.sync",
    "intervalMinutes": 60,
    "network": "any",
    "requiresCharging": false,
    "requiresBatteryNotLow": true,
    "wake": false,
    "timeoutSeconds": 60
  }
]
```

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | `[a-z0-9-]`, at most 32 characters, unique in the app |
| `action` | yes | A Keel action the app declares (`_meta."org.shipwright.keel/action"`), `[A-Za-z0-9._-]`, not marked `org.shipwright.keel/confirm` (nobody is there to confirm) |
| `intervalMinutes` | yes | One of 15, 30, 60, 120, 240, 360, 480, 720, 1440 |
| `network` | no | `"any"` (online) or `"unmetered"`; absent means no network needed |
| `requiresCharging` | no | Run only on external power. Default `false` |
| `requiresBatteryNotLow` | no | Skip below 20 % on battery (the shell's low warning). Default `false` |
| `wake` | no | May wake a suspended device. Needs `intervalMinutes` ≥ 60. Default `false` |
| `timeoutSeconds` | no | 1–600, default 60. The call is abandoned after this |

The app id must be dot-separated `[A-Za-z_][A-Za-z0-9_-]*` elements, so that
`org.marathonos.<id>` is a bus name. This field is for the manifest schema
(roadmap R13); the generator is its only reader today.

Intervals are fixed slots on wall-clock boundaries (`*:00/15`, `hourly`,
`00/4:00`, `daily`, ...), as Sailfish's nemo-keepalive `BackgroundActivity`
frequencies. All tasks on one interval elapse together, so the device wakes
once for all of them. Calendar timers also keep their schedule across a
suspend, where a monotonic `OnUnitActiveSec=` timer stops with the clock.

Constraints follow Android WorkManager's (`NetworkType`, `RequiresCharging`,
`BatteryNotLow`). An unmet constraint skips the run until the next slot. There
is no retry when the constraint is met later.

## What the platform generates

`marathon-background` is a systemd **user generator**
(`/usr/lib/systemd/user-generators/marathon-background-generator`, linked to
`/usr/libexec/marathon-background`). On every user-manager start and
`systemctl --user daemon-reload` it reads
`/usr/share/marathon-apps/*/manifest.json`, checks each task's action against
`/usr/share/keel/actions/org.marathonos.<id>.json`, and writes two units into
the generator directory:

```ini
# marathon-bg-email.sync.timer   (marathon-wake-... when "wake": true)
[Unit]
PartOf=graphical-session.target
[Timer]
OnCalendar=hourly
Persistent=true
```

```ini
# marathon-bg-email.sync.service
[Unit]
PartOf=graphical-session.target
After=graphical-session.target
# requiresCharging:
ConditionACPower=true
[Service]
Type=oneshot
Slice=background.slice
ExecCondition=/usr/libexec/marathon-background check --network=any --battery-not-low
ExecStart=busctl --user --timeout=60 call org.marathonos.email /org/shipwright/Keel/Actions org.shipwright.Keel.Actions Invoke ssa{sv} mail.sync {} 0
TimeoutStartSec=90
```

The timer is linked into `graphical-session.target.wants`, so tasks run only
in the Marathon session. A missed slot is run once: after a suspend because a
calendar timer that elapsed during it fires on resume, after a reboot or a
session restart through `Persistent=true`. Apps never ship or edit units:
the generator rebuilds them from the manifests, and rejects ids and actions
that could escape a unit line. Refused declarations are logged to the user
manager's journal (`journalctl --user -b | grep marathon-background-generator`).

The Keel call is what brings the app up. A frozen runner has released its
`org.marathonos.<id>` name (`PrepareFreeze`), so the call is bus-activated
through `marathon-activate@<id>.service`, which has the shell start the app
in the background or thaw it (`StartAppInBackground` → `wakeApp`, a 10 s
grace even in Doze). Work longer than that holds a manifest
`backgroundCapabilities` claim with `AppLifecycle.beginBackgroundTask` until
it ends.

`check` exits 0 when the constraints hold and 1 to skip:
network is NetworkManager's `State` = `CONNECTED_GLOBAL` (70), unmetered is
`Metered` = `NO` or `GUESS_NO` (unknown counts as metered); battery is the
kernel's `/sys/class/power_supply` (peripheral batteries ignored, external
power never low). Charging uses systemd's own `ConditionACPower=`.

Only system apps (`/usr/share/marathon-apps`) are read. Store-installed apps
need their Keel manifest and activation file installed and a `daemon-reload`
after install first.

### System services

A service in this repo declares its work as a plain user timer. Weather is
`marathon-bg-weather.timer` (`OnCalendar=hourly`, `Persistent=true`), which
calls `org.marathonos.Weather1.Refresh` and bus-activates weatherd if needed;
the daemon has no timer of its own. Name a timer `marathon-wake-*` only if it
is worth waking a suspended phone for.

## Waking a suspended device

A user manager cannot hold a wake alarm: on systemd 259 a user timer with
`WakeSystem=true` fails (`Failed to add realtime event source: Operation not
supported`, result `resources`). So the system arms one on the users' behalf:

1. `marathon-background-wake.service` (root, `WantedBy=sleep.target`,
   `Before=sleep.target`) runs `marathon-background arm-wake` before every
   suspend.
2. It lists the users (`loginctl --json=short list-users`) and each one's
   `marathon-wake-*` timers (`systemctl --user --machine=USER@ list-timers
   --all --output=json`), and takes the earliest next elapse, no sooner than
   30 s ahead.
3. It replaces the transient system timer `marathon-wake.timer`
   (`systemd-run --on-calendar=@T --timer-property=WakeSystem=true`), and
   writes `T` to `/run/marathon-background/wake`.
4. On a low battery (below 20 %, on battery) it arms nothing.

The wake-up is held by systemd in the kernel's alarmtimer
(`CLOCK_REALTIME_ALARM`). The alarm clock writes `/sys/class/rtc/rtc0/wakealarm`
directly; both are timers in the RTC core's queue, which programs the
earliest, so neither overwrites the other.

After the RTC wakes the device, the user timer fires because its time has
passed. The shell's `PowerManagerCpp` compares the resume time with
`/run/marathon-background/wake` (10 s before to 60 s after): on a match it
enters Doze instead of turning the screen on, so the task runs screen-off and
the device stays dozing until the person wakes it. Nothing suspends it again;
re-suspending after a maintenance window belongs with an auto-suspend policy,
which Marathon does not have.

## The modem around suspend

ModemManager handles suspend itself: Alpine builds it with
`-Dsystemd_suspend_resume=true`, so it takes a logind delay inhibitor and
quiesces and resyncs modems on `PrepareForSleep`. What is left is recovery
when the modem does not come back.

`marathon-modem-sleep.service` (in `marathon-base-config`) is bound to
`sleep.target` (`StopWhenUnneeded=yes`, `RemainAfterExit=yes`, `ExecStart`
before suspend, `ExecStop` after resume) rather than dropped into
`system-sleep/`, which systemd-suspend.service(8) calls a hack:

- `pre`: notes whether `mmcli -L` lists a modem.
- `post`: if one was there, waits 10 s for it; if it is missing, restarts
  ModemManager (`--no-block`, since this runs inside the resume transaction)
  and waits 30 s more. It logs one line,
  `event=marathon_modem_sleep state=healthy|restored|absent-before-sleep|failed`.

The unit ships disabled; device overlays choose:

| Device | Modem | Around suspend |
|---|---|---|
| Librem 5 | BroadMobi BM818, ModemManager broadmobi plugin | `marathon-modem-sleep` enabled (`sleep.target.wants` link in the overlay) |
| PinePhone | Quectel EG25-G | eg25-manager (from pmaports' `device-pine64-pinephone`): its own delay inhibitor, and a modem reset if the modem is not re-probed within 9 s. `marathon-modem-sleep` stays off so the two do not both recover |
| HackberryPi CM5, Pi 5, QEMU | none | nothing |

## Validating on a device

On the HackberryPi (no modem):

```sh
# Units and generator are installed
ls -l /usr/lib/systemd/user-generators/marathon-background-generator
systemctl cat marathon-background-wake.service
# Weather timer is scheduled in the session
systemctl --user list-timers 'marathon-*'
systemctl --user start marathon-bg-weather.service && journalctl --user -u marathon-bg-weather -n 5
# Generator output (empty until an app declares tasks)
ls /run/user/$(id -u)/systemd/generator/ | grep marathon
# check
/usr/libexec/marathon-background check --network=any; echo $?
/usr/libexec/marathon-background check --network=unmetered --battery-not-low; echo $?
```

Doze: lock with the power key and leave it dozing past the hour; the
weather run still happens (`journalctl --user -u marathon-bg-weather`
shows a start at :00).

Wake arming, as root, with a test timer standing in for a declared task.
Check `cat /sys/power/state /sys/power/mem_sleep` first: where the board
cannot suspend, stop after `cat /run/marathon-background/wake`.

```sh
systemd-run --user -M user@ --unit=marathon-wake-test.probe \
    --on-calendar=@$(( $(date +%s) + 180 )) true
systemctl start marathon-background-wake.service   # what sleep.target runs
systemctl list-timers marathon-wake.timer   # due at the probe's time
cat /run/marathon-background/wake
systemctl suspend                           # resumes about 3 min later
journalctl -b -u marathon-wake.timer -u systemd-suspend.service
```

The shell logs `System resumed from sleep for background work` (it logs to
tty1 on the devices: `cat /dev/vcs1`), the screen stays off, and the power
key wakes it as usual. A plain `systemctl suspend` woken by the power key must
still turn the screen on. With the battery below 20 % on battery,
`arm-wake` must arm nothing (`systemctl list-timers marathon-wake.timer` is
empty).

On a Librem 5 (modem): `systemctl suspend`, wake with the power key,
then `journalctl -b -u marathon-modem-sleep` shows `state=healthy` (or
`restored`), and `mmcli -L` lists the modem. A call or SMS during suspend
must still wake the device (`docs/MODEM_TESTING.md`, Phase 5).

On a PinePhone: `systemctl is-enabled marathon-modem-sleep` is `disabled`,
and `journalctl -b -u eg25-manager` shows its suspend and resume.

## Prior art

- Luma `src/luma-background`: generated user units per declared agent, and
  `org.projectluma.BackgroundWake1`, a transient `WakeSystem=` system timer
  for wake-ups the user manager cannot hold; `luma-fp6-cellular-resume` for
  the bounded modem recovery and its event line.
  <https://github.com/SimplyLuma/luma>
- Android WorkManager constraints and 15-minute minimum interval.
  <https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work>
- Sailfish nemo-keepalive `BackgroundActivity` wake-up slots.
  <https://github.com/sailfishos/nemo-keepalive>
- eg25-manager's suspend handling (`src/suspend.c`).
  <https://gitlab.com/mobian1/eg25-manager>
- systemd.timer(5) (`WakeSystem=`, `Persistent=`), systemd.service(5)
  (`ExecCondition=`), systemd-suspend.service(8), systemd.generator(7).
