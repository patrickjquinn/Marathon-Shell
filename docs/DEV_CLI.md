# Marathon dev CLI — reference + recipes

The `marathon` CLI is the primary entry point for every dev workflow —
build, deploy, snapshot, unlock, launch, tail logs, run doctor, probe
device, benchmark, save/replay test scenarios, multi-device orchestration.
Every ad-hoc SSH command you would have run has a corresponding verb.

> **Rule of thumb:** if you find yourself typing `sshpass -p marathon ssh
> root@marathon.local …`, there's already a verb for that. If there
> isn't, add one — the CLI is meant to grow with the project.

---

## Install

The CLI lives at `scripts/marathon` in this repo. Symlink into your
PATH so `marathon` works from anywhere:

```
mkdir -p ~/.local/bin ~/.local/share/bash-completion/completions
ln -sf "$(pwd)/scripts/marathon" ~/.local/bin/marathon
marathon completions bash > ~/.local/share/bash-completion/completions/marathon
```

Then set up config (one-time):

```
mkdir -p ~/.config/marathon-dev
cat > ~/.config/marathon-dev/config <<'EOF'
MARATHON_PIN=027602
# MARATHON_PASSWORD=marathon         # default; override if you changed it
# MARATHON_IMAGE=$HOME/Developer/Marathon-Image
EOF
```

Register your devices:

```
cat > ~/.config/marathon-dev/devices.conf <<'EOF'
# name  kind        ssh-host              notes
l5      librem5     root@marathon.local   USB-net 172.16.42.1 fallback
cm5     hackberry   root@marathon.local   HackberryPi CM5
EOF
```

Verify the environment:

```
marathon doctor
```

22 checks; anything red is auto-fixable with `marathon doctor --fix`.

---

## Quick reference

Run `marathon --help` for the full menu. Grouped:

### Daily-drivers
| verb | what |
|---|---|
| `marathon status` | shell pid + hash + backlight + governor + freq + battery in one command |
| `marathon deploy [--hot\|--full]` | build shell (if src changed) → push binary → restart greetd → verify hash |
| `marathon reset` | `systemctl restart greetd` + wait for shell up |
| `marathon wake` | force `bl_power=0` + brightness=200 |
| `marathon unlock [PIN]` | swipe up + PIN entry (batched via touchctl stdin) |
| `marathon snap [LABEL]` | screenshot device to `$MARATHON_SCRATCH/<LABEL>.png` |
| `marathon logs [-f] [GREP]` | tail shell log; `--warnings` filter |
| `marathon apps` | every marathon-app cgroup: uclamp / freeze / procs / state |
| `marathon launch APPID` | wake + unlock + tap the app icon |

### Interaction + live measurement
| verb | what |
|---|---|
| `marathon tap X Y` | synthetic touch tap |
| `marathon swipe X1 Y1 X2 Y2 [STEPS]` | synthetic swipe |
| `marathon power` | synthetic KEY_POWER (test wake path) |
| `marathon doze enter\|exit\|status` | Doze cycle |
| `marathon freq [--sample N]` | cpufreq time-in-state histogram |
| `marathon irqs [SECS]` | top interrupts/second |
| `marathon wakeups` | wakeup sources by event count |
| `marathon cgroup APPID` | detailed cgroup state for one app |
| `marathon monitor cgroup` | live report of every uclamp/freeze transition |
| `marathon monitor logs [PATTERN]` | tail log with regex filter |
| `marathon monitor wifi\|modem\|freq\|bl\|wakeups` | poll changes |

### Specialist probes
| verb | what |
|---|---|
| `marathon modem info` | mmcli summary |
| `marathon modem at 'AT+CFUN?'` | raw AT (stops MM, restores after) |
| `marathon modem psm on\|off\|status` | Power-Saving Mode |
| `marathon modem edrx N\|off\|status` | eDRX config |
| `marathon modem reset` | mmcli soft reset |
| `marathon wifi psm on\|off\|status` | wifi power-save |
| `marathon wifi scan` | SSID + signal |
| `marathon gov [NAME]` | show / set cpufreq governor |
| `marathon scheduler [DISK [SCHED]]` | show / set block I/O scheduler |
| `marathon fuel-gauge` | full battery + thermal report |
| `marathon backlight [VAL]` | show state or set brightness |

### App development
| verb | what |
|---|---|
| `marathon app new NAME` | scaffold app from template |
| `marathon app run [--hot] DIR` | package + install + launch |
| `marathon app package [--sign] DIR` | build `.marathon` package |
| `marathon app validate DIR` | manifest + structure check |
| `marathon app install FILE` | scp + on-device install |
| `marathon app watch DIR` | auto-repackage + install on file change (inotify) |
| `marathon app registry` | list installed marathon apps |
| `marathon app permissions APPID` | show manifest permissions |

### Doctor / self-heal
| verb | what |
|---|---|
| `marathon doctor` | 22 checks across host env + device + services + hardware |
| `marathon doctor --fix` | attempt auto-repair on known failures |

### Multi-device
| verb | what |
|---|---|
| `marathon device list` | registered devices |
| `marathon device current` | active target |
| `marathon device use NAME` | persist default |
| `marathon device add NAME KIND HOST [NOTES]` | append to devices.conf |
| `marathon device probe [NAME\|all]` | reachable? arch? uptime? |
| `marathon --device NAME <verb>` | one-shot override |
| `marathon all <verb>` | run on every reachable device in parallel |
| `marathon compare <verb>` | run on all → paste side-by-side |

### Build + lint + CI
| verb | what |
|---|---|
| `marathon build shell` | wrap pmbootstrap (mirrors --src) |
| `marathon build image DEVICE` | duranium build-image.py |
| `marathon build apps` | package every ./apps/*/ |
| `marathon flash DEVICE IMAGE` | L5 uuu / CM5 dd |
| `marathon fmt [--fix]` | clang-format + qmllint sweep |
| `marathon lint [FILES]` | clang-tidy on staged .cpp |
| `marathon audit` | fmt + lint + qmllint end-to-end |
| `marathon changelog [SINCE]` | commits since tag / last 20 |

### Sessions + bench
| verb | what |
|---|---|
| `marathon session new NAME` | create empty session |
| `marathon session record NAME <verb>` | append a step |
| `marathon session run NAME` | replay every step |
| `marathon session list\|rm\|diff` | manage |
| `marathon bench doze\|wake\|foreground-boost\|battery-idle` | canned bench |

### Onboarding
| verb | what |
|---|---|
| `marathon quickstart` | 9-step guided walkthrough |
| `marathon docs [TOPIC]` | open docs/TOPIC.md in $PAGER |
| `marathon completions bash\|zsh\|fish` | shell completion |

---

## Recipes

### "I edited shell C++ — how do I get it on the device?"

```
marathon deploy
```

Auto-detects the current `pkgrel` from `MARATHON_IMAGE/packages/marathon-shell/APKBUILD`, builds via pmbootstrap if the APK for that rev is missing, extracts the binary, pushes to `/tmp` on device, atomic-replaces `/usr/bin/marathon-shell-bin`, restarts greetd, verifies the hash on both sides matches. One command, ~60 seconds cold, ~15 seconds if the APK is already cached.

### "I edited a QML file — do I need to redeploy?"

The shell's QML is qrc-embedded (compiled into the binary), so yes:
`marathon deploy`. `marathon-ui`'s QML is disk-imported and can be
hot-deployed via `scripts/hot-deploy.sh`, but the CLI hasn't wrapped
that yet — TODO for Phase 2.5.

### "Is my device set up correctly?"

```
marathon doctor
```

If anything's red:

```
marathon doctor --fix
```

### "What's happening on the device right now?"

```
marathon status              # snapshot: shell + display + cpu + battery
marathon apps                # every app's cgroup state
marathon logs                # last 30 lines of shell log
```

For a live view:

```
marathon monitor cgroup      # every uclamp/freeze transition
marathon monitor logs        # tail crash.log
marathon logs -f WARNING     # tail, filtered to warnings
```

### "How do I test Doze on a fresh boot?"

```
marathon session new doze-regression
marathon session record doze-regression wake
marathon session record doze-regression unlock
marathon session record doze-regression "snap doze-active"
marathon session record doze-regression "bench doze"
marathon session record doze-regression "snap doze-in-doze"
marathon session record doze-regression "bench wake"
marathon session record doze-regression "snap doze-back"
marathon session record doze-regression apps
marathon session run doze-regression
```

Re-run whenever you want to check for regressions:

```
marathon session run doze-regression
```

### "Bench the foreground boost"

Requires an app to be foreground first:

```
marathon launch settings
marathon bench foreground-boost
```

Two-stage check:
- Stage A — the current foreground app has `cpu.uclamp.min=30`.
- Stage B — launching a different running app swaps: old→0, new→30.

### "I want to test on both L5 and CM5"

Register both in `devices.conf`, then:

```
marathon all status
marathon all doctor
marathon --device cm5 deploy
```

For a side-by-side comparison:

```
marathon compare freq
marathon compare fuel-gauge
```

### "I need to run a raw AT command against the modem"

```
marathon modem at 'AT+CFUN?'
```

The CLI stops ModemManager briefly (so we can grab /dev/ttyUSB2),
runs the AT, then restarts MM. Call/data connection is unaffected
beyond a ~5-second pause.

### "I'm building a new app"

```
marathon app new my-app
cd my-app
# edit main.qml, manifest.json
marathon app validate .
marathon app watch .          # auto-package + install on save
# in another terminal:
marathon monitor cgroup        # see the app appear
marathon launch my-app
```

### "The device is unreachable"

Try USB-net fallback (L5 only):

```
marathon --host root@172.16.42.1 status
```

Or probe both:

```
marathon device probe all
```

### "I just committed — is my codebase clean?"

```
marathon audit
```

Runs `clang-format --dry-run --Werror`, `qmllint`, and `clang-tidy`
on staged files. Same checks the pre-commit hook runs.

### "I want to profile CPU frequency behavior over 30 seconds"

```
marathon freq --sample 30
```

Or continuously:

```
marathon monitor freq
```

---

## Configuration

### Files

| file | purpose |
|---|---|
| `~/.config/marathon-dev/config` | env-style KEY=VAL overrides for defaults |
| `~/.config/marathon-dev/devices.conf` | one line per device: `name kind host [notes]` |
| `~/.config/marathon-dev/sessions/*.session` | saved test scenarios |
| `~/.marathon-secrets/askpass.sh` | sudo askpass — copied to `/tmp/askpass.sh` on demand |

### Env variables (override config)

| var | default | notes |
|---|---|---|
| `MARATHON_HOST` | first device in devices.conf | full `user@host` |
| `MARATHON_DEVICE` | first in devices.conf | picks a device by name |
| `MARATHON_PASSWORD` | `marathon` | SSH password |
| `MARATHON_PIN` | (unset — must be configured) | 6-digit unlock PIN |
| `MARATHON_SRC` | resolved from CLI location | Marathon-Shell repo root |
| `MARATHON_IMAGE` | `~/Developer/Marathon-Image` | Marathon-Image repo root |
| `MARATHON_SCRATCH` | session-specific tmp dir | scratchpad for snaps/APKs |
| `MARATHON_VERBOSE` | 0 | 1 = show debug traces |
| `MARATHON_QUIET` | 0 | 1 = suppress info/step lines |

### Flags

| flag | purpose |
|---|---|
| `--device`, `-d` NAME | one-shot device override |
| `--host`, `-H` HOST | one-shot SSH host override |
| `--verbose`, `-v` | debug output |
| `--quiet`, `-q` | suppress info/step |
| `--help`, `-h` | help |

---

## Architecture

```
scripts/
  marathon                    # dispatcher: parse flags, load modules, dispatch
  marathon.d/
    common.sh                 # SSH/config/emit helpers + device resolution
    phase1.sh                 # status, deploy, reset, wake, unlock, snap, logs, apps, launch
    phase2.sh                 # tap, swipe, power, doze, freq, irqs, wakeups, cgroup, monitor
    phase3.sh                 # modem, wifi, gov, scheduler, fuel-gauge, backlight
    phase4.sh                 # app new/run/package/validate/install/watch/registry/permissions
    phase5.sh                 # doctor + --fix
    phase6.sh                 # device use/add/probe, all, compare
    phase7.sh                 # build, flash, fmt, lint, audit, changelog
    phase8.sh                 # session, bench
    phase9.sh                 # quickstart, docs, completions
```

### Adding a new verb

Every verb is a shell function named `cmd_<verb>` (or
`cmd_<verb>_<subverb>` for grouped commands). The dispatcher looks
them up by name. Example:

```bash
# in scripts/marathon.d/phase3.sh
cmd_thermal() {
    marathon::ssh 'for zone in /sys/class/thermal/thermal_zone*/; do
        name=$(cat "$zone/type" 2>/dev/null)
        temp=$(cat "$zone/temp" 2>/dev/null)
        awk -v n="$name" -v t="$temp" "BEGIN{printf \"  %-20s %.1f°C\n\", n, t/1000}"
    done'
}
```

Then `marathon thermal` works immediately. No dispatcher change.

For a grouped verb (`marathon modem info` → `cmd_modem_info`), define
one function per subverb. The dispatcher finds the longest matching
prefix and hands the rest as args.

Add it to `marathon::usage` in `common.sh` and update this file.

---

## Troubleshooting

| symptom | fix |
|---|---|
| `marathon: command not found` | Symlink not in PATH — see Install |
| `askpass: not found` | `cp ~/.marathon-secrets/askpass.sh /tmp/askpass.sh && chmod 700 /tmp/askpass.sh` (or `marathon doctor --fix`) |
| `unreachable` | Try `marathon --host root@172.16.42.1 status` (USB-net); confirm device is on the same LAN |
| `unlock` types dots but device stays at PIN screen | Some digit dropped. `marathon snap` to see how many dots landed, then either re-run `marathon unlock` (it's idempotent) or tap the missing digit(s) via `marathon tap` |
| `launch APPID` reports "already running — tapping to bring foreground" but the app stays frozen | Icon-tap missed. Use `marathon snap` to find the actual icon location and `marathon tap X Y` directly |
| `bench doze` reports "timed out waiting for bl_power=4" | Shell may be in an odd state; try `marathon reset` then re-bench |
| CLI shows "0/22 pass" from `marathon doctor` | Almost certainly askpass — see above |

---

## Related docs

- `docs/DEVELOPMENT_WORKFLOW.md` — source vs installed paths, edit rules
- `docs/APP_DEVELOPMENT.md` — writing a new Marathon app
- `docs/MAPP_GUIDE.md` — MApp lifecycle
- `docs/ARCHITECTURE.md` — the shell's process model
- `docs/UI_DESIGN_SYSTEM.md` — design tokens + Marathon-Doze power model
