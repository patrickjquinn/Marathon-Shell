# Marathon Shell - DBus Implementation Status

## ✅ COMPLETED (Critical Priority)

### 1. Bluetooth Pairing Agent ✓
**Status: FULLY IMPLEMENTED**

**Files:**
- `shell/src/bluetoothagent.h`
- `shell/src/bluetoothagent.cpp`

**Implementation:**
- ✅ Implements `org.bluez.Agent1` interface
- ✅ Handles PIN code requests (`RequestPinCode`)
- ✅ Handles passkey requests (`RequestPasskey`)
- ✅ Handles passkey display (`DisplayPasskey`, `DisplayPinCode`)
- ✅ Handles confirmation requests (`RequestConfirmation`)
- ✅ Handles authorization requests (`RequestAuthorization`, `AuthorizeService`)
- ✅ Registered with BlueZ as "KeyboardDisplay" capability (supports all pairing methods)
- ✅ Integrated into `BluetoothManager`
- ✅ Emits signals to UI for user interaction
- ✅ Handles pairing cancellation

**Testing Required:**
- Pair with various device types (headphones, keyboard, phone, etc.)
- Test PIN entry
- Test passkey confirmation
- Test pairing cancellation

---

### 2. Telephony Service (ModemManager Voice API) ✓
**Status: FULLY IMPLEMENTED**

**Files:**
- `shell/src/telephonyservice.h` (updated)
- `shell/src/telephonyservice.cpp` (completely rewritten)

**Implementation:**
- ✅ Connects to `org.freedesktop.ModemManager1`
- ✅ Modem discovery and monitoring
- ✅ Dial functionality (`CreateCall` + `Start`)
- ✅ Answer incoming calls (`Accept`)
- ✅ Hangup calls (`Hangup`)
- ✅ DTMF tone support (`SendDtmf`)
- ✅ Incoming call detection and monitoring
- ✅ Call state tracking (idle/dialing/ringing/incoming/active/held/waiting/terminated)
- ✅ Property change monitoring via DBus signals
- ✅ Automatic modem reconnection

**Testing Required:**
- Make outgoing calls
- Receive incoming calls
- Test DTMF tones
- Test call states
- Test modem hotplug

---

### 3. SMS Service (ModemManager Messaging API) ✓
**Status: FULLY IMPLEMENTED**

**Files:**
- `shell/src/smsservice.h` (unchanged)
- `shell/src/smsservice.cpp` (completely rewritten)

**Implementation:**
- ✅ Connects to `org.freedesktop.ModemManager1.Modem.Messaging`
- ✅ Send SMS via ModemManager (`Create` + `Send`)
- ✅ Receive SMS with automatic monitoring
- ✅ SQLite database for message storage
- ✅ Conversation management
- ✅ Unread message tracking
- ✅ Mark messages as read
- ✅ Delete conversations
- ✅ Automatic SIM storage cleanup (deletes from SIM after storing locally)
- ✅ Duplicate message prevention
- ✅ Contact name resolution support

**Testing Required:**
- Send SMS messages
- Receive SMS messages
- Test conversation threading
- Test database persistence
- Test with multiple conversations

---

### 4. Mobile Data Control (ModemManager Bearer API) ✓
**Status: FULLY IMPLEMENTED**

**Files:**
- `shell/src/modemmanagercpp.cpp` (updated)

**Implementation:**
- ✅ Enable mobile data via `org.freedesktop.ModemManager1.Modem.Simple.Connect`
- ✅ Disable mobile data via `org.freedesktop.ModemManager1.Modem.Simple.Disconnect`
- ✅ Uses carrier default APN when none specified
- ✅ State tracking (`dataEnabled`, `dataConnected`)
- ✅ Signal emissions for UI updates

**Testing Required:**
- Enable/disable mobile data
- Test data connection with carrier
- Test APN auto-detection

---

## 🚧 IN PROGRESS / REMAINING

### 5. APN Configuration Management
**Status: NOT STARTED**
**Priority: HIGH**

**What's Needed:**
- UI for APN settings (name, APN, username, password, auth type, MMSC, MCC, MNC)
- Store APN configurations in settings database
- Pass APN to ModemManager Simple.Connect: `properties["apn"] = "internet"`
- Support multiple APN profiles
- APN auto-detection from carrier database

**Files to Create:**
- `shell/src/apnmanager.h`
- `shell/src/apnmanager.cpp`
- `apps/settings/pages/APNSettingsPage.qml`

---

### 6. PulseAudio DBus API
**Status: NOT STARTED**
**Priority: HIGH**

**Current Issue:**
- `AudioManagerCpp` uses shell commands (`pactl`) instead of DBus

**What's Needed:**
- Connect to `org.PulseAudio.Core1` on session bus
- Use `org.PulseAudio.Core1.Device` for volume control
- Use `org.PulseAudio.Core1.Sink` for output device management
- Monitor property changes for real-time volume updates
- Support per-app volume control via `org.PulseAudio.Core1.Stream`

**DBus Interface:**
```cpp
QDBusInterface pulseAudio(
    "org.PulseAudio.Core1",
    "/org/pulseaudio/core1",
    "org.PulseAudio.Core1",
    QDBusConnection::sessionBus()
);
```

---

### 7. Screen Rotation (iio-sensor-proxy)
**Status: NOT STARTED**
**Priority: HIGH**

**What's Needed:**
- Connect to `net.hadess.SensorProxy` on system bus
- Monitor `HasAccelerometer` property
- Subscribe to `PropertiesChanged` signal
- Read `AccelerometerOrientation` property
- Map orientation to screen rotation: normal, bottom-up, left-up, right-up
- Apply rotation to Wayland compositor

**DBus Interface:**
```cpp
QDBusInterface sensorProxy(
    "net.hadess.SensorProxy",
    "/net/hadess/SensorProxy",
    "net.hadess.SensorProxy",
    QDBusConnection::systemBus()
);
```

**Files to Create:**
- `shell/src/rotationmanager.h`
- `shell/src/rotationmanager.cpp`

---

### 8. Location Services (Geoclue2)
**Status: NOT STARTED**
**Priority: MEDIUM**

**What's Needed:**
- Connect to `org.freedesktop.GeoClue2` on system bus
- Get client via `GetClient` method
- Set desktop ID and request accuracy level
- Start location updates with `Start` method
- Monitor `LocationUpdated` signal
- Provide latitude, longitude, accuracy, altitude, speed, heading

**DBus Interface:**
```cpp
QDBusInterface geoclue(
    "org.freedesktop.GeoClue2",
    "/org/freedesktop/GeoClue2/Manager",
    "org.freedesktop.GeoClue2.Manager",
    QDBusConnection::systemBus()
);
```

**Files to Create:**
- `shell/src/locationmanager.h`
- `shell/src/locationmanager.cpp`

---

### 9. WiFi Hotspot/Tethering
**Status: NOT STARTED**
**Priority: MEDIUM**

**What's Needed:**
- Use NetworkManager `AddConnection` with mode="ap"
- Configure SSID, password, security
- Activate connection with `ActivateConnection`
- Monitor connected clients
- Support USB tethering via `ipv4.method=shared`
- Support Bluetooth tethering

**NetworkManager Connection Settings:**
```cpp
QVariantMap connection;
connection["type"] = "802-11-wireless";
connection["id"] = "Marathon Hotspot";

QVariantMap wireless;
wireless["mode"] = "ap";  // Access Point mode
wireless["ssid"] = ssid.toUtf8();

QVariantMap wirelessSecurity;
wirelessSecurity["key-mgmt"] = "wpa-psk";
wirelessSecurity["psk"] = password;
```

**Files to Update:**
- `shell/src/networkmanagercpp.h` (add hotspot methods)
- `shell/src/networkmanagercpp.cpp` (implement hotspot)

---

### 10. VPN Management
**Status: NOT STARTED**
**Priority: LOW**

**What's Needed:**
- List VPN connections via NetworkManager
- Import VPN configurations (.ovpn, .conf, etc.)
- Activate/deactivate VPN connections
- Monitor VPN status
- Support OpenVPN, WireGuard, IPSec, PPTP

**Files to Create:**
- `shell/src/vpnmanager.h`
- `shell/src/vpnmanager.cpp`

---

### 11. Haptic/Vibration Feedback
**Status: NOT STARTED**
**Priority: LOW**

**What's Needed:**
- Control `/sys/class/leds/vibrator/brightness` for vibration
- Or use force-feedback API via `/dev/input/eventX`
- Support vibration patterns (short, long, pattern)
- Integrate with touch feedback

**Files to Create:**
- `shell/src/hapticmanager.h`
- `shell/src/hapticmanager.cpp`

---

### 12. NFC Support
**Status: NOT STARTED**
**Priority: LOW**

**What's Needed:**
- Connect to `org.neard` on system bus
- Detect NFC adapters
- Read NFC tags
- Write NFC tags
- P2P data exchange
- Card emulation mode

**DBus Interface:**
```cpp
QDBusInterface neard(
    "org.neard",
    "/",
    "org.freedesktop.DBus.ObjectManager",
    QDBusConnection::systemBus()
);
```

**Files to Create:**
- `shell/src/nfcmanager.h`
- `shell/src/nfcmanager.cpp`

---

### 13. Brightness Readback & Auto-Brightness
**Status: NOT STARTED**
**Priority: MEDIUM**

**What's Needed:**
- Read current brightness from `/sys/class/backlight/*/brightness`
- Monitor ambient light sensor via `SensorManagerCpp`
- Implement auto-brightness algorithm
- Store user brightness curve preferences
- Smooth brightness transitions

**Files to Update:**
- `shell/src/displaymanagercpp.h` (add getCurrentBrightness)
- `shell/src/displaymanagercpp.cpp` (implement readback + auto)

---

### 14. org.freedesktop.Notifications Compatibility
**Status: NOT STARTED**
**Priority: LOW**

**What's Needed:**
- Implement `org.freedesktop.Notifications` spec
- Support `Notify` method (app_name, replaces_id, app_icon, summary, body, actions, hints, timeout)
- Support `CloseNotification` method
- Support `GetCapabilities` method
- Support `GetServerInformation` method
- Emit `NotificationClosed` and `ActionInvoked` signals
- Bridge to custom `org.marathon.NotificationService`

**DBus Interface:**
```cpp
Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")
```

**Files to Create:**
- `shell/src/freedesktopnotifications.h`
- `shell/src/freedesktopnotifications.cpp`

---

## 📊 IMPLEMENTATION SUMMARY

### Completed: 4/14 (29%)
- ✅ Bluetooth Pairing Agent
- ✅ Telephony (Voice Calls)
- ✅ SMS Messaging
- ✅ Mobile Data Control

### High Priority Remaining: 3
- APN Configuration
- PulseAudio DBus API
- Screen Rotation

### Medium Priority Remaining: 3
- Location Services
- WiFi Hotspot
- Brightness Auto-Adjust

### Low Priority Remaining: 4
- VPN Management
- Haptic Feedback
- NFC Support
- Freedesktop Notifications

---

## 🔨 NEXT STEPS

1. **Compile and Test Current Implementation:**
   ```bash
   cd /home/patrickquinn/Developer/Marathon-Shell/build
   cmake ..
   make -j$(nproc)
   ```

2. **Test Critical Features:**
   - Bluetooth pairing with various devices
   - Make/receive phone calls
   - Send/receive SMS
   - Enable/disable mobile data

3. **Implement High Priority Items:**
   - Start with PulseAudio DBus (quick win, big impact)
   - Then screen rotation (essential for smartphone)
   - Then APN configuration (completes cellular functionality)

4. **Create UI Components:**
   - Bluetooth pairing dialogs
   - Call screens
   - SMS conversations
   - APN settings page

---

## 📝 NOTES

### Build Requirements
All new services require Qt6 DBus module (already in CMakeLists.txt).

### Runtime Requirements
- BlueZ 5.x for Bluetooth
- ModemManager 1.6+ for telephony/SMS
- iio-sensor-proxy for screen rotation
- Geoclue2 for location
- PulseAudio for audio
- NetworkManager for network/hotspot
- neard for NFC (optional)

### Polkit Policies
Some operations may require polkit policies:
- Bluetooth pairing (usually allowed for active session)
- ModemManager operations (may need policy)
- NetworkManager hotspot (may need policy)
- Brightness control via logind (usually allowed)

---

**Last Updated:** 2025-10-31
**Status:** 29% Complete (4/14 features)
**Next Milestone:** High priority items (7/14 = 50%)

