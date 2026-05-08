# Modem Field Test Plan

This is the validation plan for telephony, SMS, MMS, suspend/wake, and audio
routing on real hardware. The dev box (Apple Silicon Linux) has no modem, so
none of this can be exercised before deploying to a target with ModemManager
talking to actual radio hardware.

## Targets

In order of expected reliability:

1. **PinePhone (BraveHeart / Pro)** with the **Quectel EG25-G** modem and the
   `eg25-manager` daemon running. postmarketOS or Mobian recommended.
2. **OnePlus 6 / 6T** running postmarketOS-edge mainline (2024.06+ kernel).
3. **Pixel 3a / Pixel 5** via postmarketOS Halium-free mainline (modem support
   is partial — calls and SMS work, MMS is touch-and-go).

Do not field-test on the Librem 5 yet — its BM818 modem firmware has long-
standing issues with some carriers (T-Mobile US specifically).

## Prerequisites on the device

```sh
# Install required services
sudo apk add modemmanager mmsd-tng mobile-broadband-provider-info \
             power-profiles-daemon bluez

# Enable services
sudo rc-update add modemmanager default      # OpenRC
# OR
sudo systemctl enable --now ModemManager.service

# mmsd-tng is bus-activated — no enable step needed.
# Confirm the daemon spawns on first call:
busctl --user list | grep -i mms || \
  dbus-send --session --dest=org.ofono.mms / org.freedesktop.DBus.Peer.Ping
```

The `setup-system.sh` script in this repo automates everything above when run
under `sudo` — that is the recommended path.

## Phase 1 — Modem readiness

Before running any tests, the modem must be in a usable state:

```sh
# Confirm ModemManager sees a modem
mmcli -L

# Sample healthy output:
#     /org/freedesktop/ModemManager1/Modem/0 [Quectel] EG25-G

# Confirm the modem is ENABLED + REGISTERED + has SIGNAL:
mmcli -m 0
# Expect:  state: registered (home or roaming)
#          signal quality: > 30%
```

If `state: locked`, the SIM PIN is set. Unlock:

```sh
mmcli -m 0 --pin=NNNN
```

Pre-flight checklist:

- [ ] `mmcli -L` shows the modem object
- [ ] `mmcli -m 0` shows `state: registered`
- [ ] `mmcli -m 0` shows operator + signal > 25%
- [ ] `nmcli c` shows a mobile broadband connection (only relevant for data
      tests)

## Phase 2 — Voice calls

### Outgoing dial

1. Launch the phone app (tap the icon, or `dbus-send` `Navigation.LaunchApp
   string:phone`).
2. Dial a known number (your own desk phone or a test landline).
3. Tap **Call**.
4. Verify:
   - [ ] Call screen shows the dialed number
   - [ ] Active call state propagates: `mmcli -m 0 --voice-list-calls` should
         list the new call with state `active`
   - [ ] Audio routes through the **earpiece** (handset) by default
   - [ ] Speakerphone toggle in `ActiveCallPage` switches the route
   - [ ] DTMF: tap a digit during the call — caller hears the tone

### Incoming dial

1. From a different number, call the device.
2. Verify:
   - [ ] **Device wakes from suspend** if it was idle (this is the critical
         radio-wakeup test — see "Phase 5" if it fails)
   - [ ] `IncomingCallOverlay` shows on top of the lock screen
   - [ ] Caller-ID resolves to a contact name when known
   - [ ] Tap **Answer** — call goes active, audio routes to earpiece
   - [ ] Tap **Hangup** — `state: terminated` in mmcli, audio routes back to
         media

### Hangup edge cases

- [ ] Caller hangs up first → device returns to idle, no zombie call entries
- [ ] Tap **Hangup** mid-ring → call is rejected, no missed-call left in
      history (or one missed-call entry is logged — check policy)
- [ ] Network drop mid-call → call ends gracefully, error state propagates

## Phase 3 — Emergency calling

**Test in a country where 112 routes to a non-emergency test number** OR
coordinate with your local PSAP for a planned drill. **Never** field-test 911
or 112 without authorisation.

For unit-level confidence without involving a PSAP:

1. From the lock screen (without unlocking) tap **Emergency**.
2. Verify the phone app launches in restricted mode:
   - [ ] Tab bar shows only "Emergency"
   - [ ] No History / Contacts tabs
   - [ ] Dialer is the only entry surface
3. Dial `*#06#` (IMEI display, harmless on every carrier):
   - [ ] On real hardware this will display the IMEI. On dev hardware the
         modem rejects with `EmergencyOnly` and the call fails — that is
         expected if no SIM is registered.
4. Confirm the audit log:
   ```sh
   journalctl --user -t marathon-shell | grep -i 'Emergency dial'
   # Expect: [SECURITY] Emergency dial: number=*#06# modem=/org/.../Modem/0 operator=...
   ```

### SIM-locked emergency

Lock the SIM with PIN (if the carrier permits) and reboot. Without entering the
PIN:

1. From the lock screen tap **Emergency**.
2. Dialer should still be reachable.
3. Dialing `112` should be accepted by the modem even with SIM locked
   (3GPP TS 22.101 §10).

## Phase 4 — SMS

### Outgoing SMS (single recipient)

1. Open the messages app, compose to a known number, send "test 1".
2. Verify:
   - [ ] Message lands on the recipient
   - [ ] `messages` app marks it sent, conversation thread updates
   - [ ] `mmcli -m 0 --messaging-list-sms` lists the SMS

### Incoming SMS

1. Send an SMS from another phone to the device.
2. Verify:
   - [ ] Notification appears (lock screen or notification shade)
   - [ ] Tapping the notification opens the conversation in `messages`
   - [ ] Conversation thread shows the new message

### Group SMS / MMS

1. Compose a message to **two or more** recipients.
2. Send.
3. Verify:
   - [ ] Marathon routes via `mmsd-tng` (not ModemManager.Messaging) — check
         logs for `[MmsManager] MMS submitted to N recipients`
   - [ ] All recipients receive the message
   - [ ] Replies fan out to all recipients (group thread on iOS / Android
         clients should display as a group)

### Image / picture MMS

1. Compose a message with an image attached.
2. Send.
3. Verify:
   - [ ] Recipient receives the image
   - [ ] mmsd-tng staging dir (`/tmp/marathon/mms-out/`) is cleaned up after
         `Status=sent`

### Carrier-specific

US MVNOs (Google Fi, US Mobile on Verizon side) drop multi-recipient SMS at
the SMSC. Confirm group routing always uses MMS regardless of carrier — see
`SMSService::sendMultiRecipient` heuristic.

## Phase 5 — Suspend / wake

This is where modem integration most often breaks on Linux mobile.

### Idle → suspend → incoming call wake

1. With the device locked and screen blank (idle suspend triggered by
   `org.freedesktop.login1.Manager.Suspend` after `IdleAction` timeout):
   ```sh
   sudo systemctl suspend
   ```
2. Wait 10 seconds.
3. From another phone, dial the device.
4. Expected outcome:
   - [ ] Device wakes within 5 seconds of the modem asserting its wakeup IRQ
   - [ ] Lock screen shows incoming-call overlay
   - [ ] Audio routes when answered

If the device does NOT wake:
- Check the modem driver registered as a wakeup source:
  ```sh
  cat /sys/class/wakeup/*/name
  # Should include something like "uart" or "modem-rdy"
  cat /sys/power/wake_lock 2>/dev/null
  ```
- Check `journalctl -t modemmanager` for `RESUMING` after the wake event
- The shell's lifelong delay-inhibit lock is held by `PowerManagerCpp`:
  ```sh
  systemd-inhibit --list | grep marathon-shell
  # Expect: marathon-shell ... sleep ... delay
  ```

### Idle → suspend → incoming SMS wake

Same procedure with SMS. SMS is shorter-lived so the wake window matters less,
but the device should still wake and surface the notification.

### Active call → suspend block

1. Place an outgoing call.
2. While the call is active, run:
   ```sh
   systemd-inhibit --list | grep marathon
   # Expect a "block" inhibit with reason "Active call inhibits system suspend"
   ```
3. Attempt to suspend manually:
   ```sh
   sudo systemctl suspend  # Should be blocked or warn
   ```
4. Hang up.
5. Confirm the `block` inhibit was released — `systemd-inhibit --list` should
   no longer show it.

## Phase 6 — Audio routing

Real audio routing requires PipeWire's `VoiceCall` profile to be defined in
WirePlumber for the modem audio device. On PinePhone with `eg25-manager`, this
is preconfigured. On other devices, you may need to write a WirePlumber
config snippet.

1. Start a call.
2. `pw-cli ls Node | grep -i call` — expect a node like `alsa_output.platform-modem.HiFi__Earpiece__sink`.
3. Toggle speakerphone — confirm the active sink switches.
4. Mute — confirm `Audio.SetCallMuted(true)` mutes the source feeding the
   modem (verify caller hears nothing).
5. End the call — sinks revert to media defaults.

If audio doesn't route at all on call start, the WirePlumber `voice-call`
policy file is missing or wrong.

## Phase 7 — Network registration recovery

Toggle airplane mode on, then off:

```sh
nmcli r wwan off  # disable mobile
sleep 3
nmcli r wwan on
```

Verify within 30s:
- [ ] `mmcli -m 0` shows `state: registered` again
- [ ] Marathon's `ModemManagerCpp.registered` is true (check Quick Settings)
- [ ] Inbound SMS to the device queued during airplane mode arrives
- [ ] An outgoing call to a known number succeeds

## Smoke checklist

If you have 5 minutes on a real device, just run:

```sh
mmcli -L                       # Modem present
mmcli -m 0 | grep state        # registered
journalctl --user -t marathon-shell -f &  # tail logs

# (a) place a 5-second test call to your own desk phone
# (b) send an SMS to your own number
# (c) sudo systemctl suspend; (incoming call from another phone) — does it wake?
```

Pass/fail summary should drive the release-readiness decision per device.
