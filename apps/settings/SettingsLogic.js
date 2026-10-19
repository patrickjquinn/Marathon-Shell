.pragma library

// Route names (deep links, search) to page files under pages/.
const pages = {
    wifi: "WiFiPage.qml",
    bluetooth: "BluetoothPage.qml",
    cellular: "CellularPage.qml",
    display: "DisplayPage.qml",
    scale: "DisplayPage.qml",
    screentimeout: "DisplayPage.qml",
    ambience: "AmbiencePage.qml",
    wallpaper: "AmbiencePage.qml",
    datetime: "DateTimePage.qml",
    sound: "SoundPage.qml",
    notifications: "NotificationsPage.qml",
    storage: "StoragePage.qml",
    battery: "BatteryPage.qml",
    security: "SecurityPage.qml",
    about: "AboutPage.qml",
    licenses: "LicensesPage.qml",
    tos: "TermsPage.qml",
    privacy: "PrivacyPage.qml",
    updates: "UpdatesPage.qml",
    keyboard: "KeyboardPage.qml",
    appmanager: "AppManagerPage.qml",
    appinfo: "AppManagerPage.qml",
    accounts: "AccountsPage.qml",
    quicksettings: "QuickSettingsPage.qml",
    hiddenapps: "HiddenAppsPage.qml",
    appsort: "AppLayoutPage.qml",
    store: "StorePage.qml",
    erase: "ErasePage.qml",
    android: "AndroidPage.qml",
    androidapps: "AndroidAppsPage.qml",
    androidaccess: "AndroidAccessListPage.qml",
    mms: "MmsPage.qml",
    permissions: "PermissionsPage.qml"
};

function pageFile(route) {
    const name = String(route || "").replace(/^\/+/, "").split(/[/?]/)[0].toLowerCase();
    return pages[name] || "";
}

// "appmanager/notes" -> "notes"; "androidaccess/all_files/org.example" -> "all_files/org.example".
function routeArgument(route) {
    return String(route || "").replace(/^\/+/, "").split("?")[0].split("/").slice(1).join("/");
}

// What the main page lists, in order, and what search looks through.
const sections = [
    {
        title: qsTr("Connectivity"),
        entries: [
            { page: "wifi", title: qsTr("Wi-Fi"), icon: "image://theme/icon-m-wlan", keywords: "wifi wireless network internet wlan password" },
            { page: "bluetooth", title: qsTr("Bluetooth"), icon: "image://theme/icon-m-bluetooth", keywords: "pair devices headphones speaker wireless" },
            { page: "cellular", title: qsTr("Mobile network"), icon: "image://theme/icon-m-cellular", keywords: "cellular data roaming sim carrier operator 4g 5g lte" }
        ]
    },
    {
        title: qsTr("Device"),
        entries: [
            { page: "display", title: qsTr("Display"), icon: "image://theme/icon-m-display", keywords: "screen brightness rotation auto-brightness reduce motion animation timeout sleep scale text size" },
            { page: "ambience", title: qsTr("Ambience"), icon: "image://theme/icon-m-ambience", keywords: "wallpaper background home screen theme colour color" },
            { page: "sound", title: qsTr("Sounds"), icon: "image://theme/icon-m-volume", keywords: "volume ringtone alarm audio mute" },
            { page: "notifications", title: qsTr("Notifications"), icon: "image://theme/icon-m-notifications", keywords: "alerts lock screen per-app do not disturb" },
            { page: "quicksettings", title: qsTr("Quick settings"), icon: "image://theme/icon-m-toggle", keywords: "tiles shade toggles" },
            { page: "datetime", title: qsTr("Date and time"), icon: "image://theme/icon-m-clock", keywords: "time zone timezone clock 24-hour 12-hour format city" },
            { page: "battery", title: qsTr("Battery"), icon: "image://theme/icon-m-battery", keywords: "power saver profile charging" },
            { page: "storage", title: qsTr("Storage"), icon: "image://theme/icon-m-storage", keywords: "disk space memory usage free" },
            { page: "keyboard", title: qsTr("Keyboard"), icon: "image://theme/icon-m-keyboard", keywords: "language autocorrect predictions typing capitalize" }
        ]
    },
    {
        title: qsTr("Security and accounts"),
        entries: [
            { page: "security", title: qsTr("Security"), icon: "image://theme/icon-m-device-lock", keywords: "pin password lock fingerprint biometric encryption" },
            { page: "permissions", title: qsTr("App permissions"), icon: "image://theme/icon-m-privacy", keywords: "privacy camera microphone location contacts calendar files notifications android apps allow deny revoke" },
            { page: "accounts", title: qsTr("Accounts"), icon: "image://theme/icon-m-people", keywords: "carddav caldav sync nextcloud contacts calendar" }
        ]
    },
    {
        title: qsTr("Apps"),
        entries: [
            { page: "appmanager", title: qsTr("Installed apps"), icon: "image://theme/icon-m-apps", keywords: "apps uninstall installed remove manager" },
            { page: "android", title: qsTr("Android apps"), icon: "image://theme/icon-m-android", keywords: "android apk play permissions special access reset" },
            { page: "hiddenapps", title: qsTr("Hidden apps"), icon: "image://theme/icon-m-hidden", keywords: "hide drawer" },
            { page: "appsort", title: qsTr("App grid"), icon: "image://theme/icon-m-app-grid", keywords: "grid columns icons layout filter desktop native search badges" },
            { page: "store", title: qsTr("App Store"), icon: "image://theme/icon-m-package", keywords: "store flathub f-droid fdroid sources phone mobile desktop automatic updates metered anti-features" }
        ]
    },
    {
        title: qsTr("System"),
        entries: [
            { page: "updates", title: qsTr("Software updates"), icon: "image://theme/icon-m-update", keywords: "upgrade version release channel" },
            { page: "about", title: qsTr("About device"), icon: "image://theme/icon-m-about", keywords: "device name version model kernel build licenses legal terms privacy" },
            { app: "terminal", title: qsTr("Terminal"), icon: "image://theme/icon-m-terminal", keywords: "shell command console" },
            { page: "erase", title: qsTr("Erase all content"), icon: "image://theme/icon-m-delete", keywords: "factory reset wipe delete everything restore sell" }
        ]
    }
];

function words(text) {
    return String(text || "").toLowerCase().split(/[\s-]+/).filter(w => w.length > 0);
}

// Entries where every query word starts a word of the title, section or keywords.
function search(query) {
    const wanted = words(query);
    if (wanted.length === 0)
        return [];
    const matches = (hay) => wanted.every(w => hay.some(h => h.indexOf(w) === 0));
    // Entries whose own title matches come first: Enter opens the first.
    const byTitle = [];
    const others = [];
    sections.forEach(section => section.entries.forEach(entry => {
        if (!matches(words(entry.title + " " + section.title + " " + entry.keywords)))
            return;
        const hit = Object.assign({ section: section.title }, entry);
        (matches(words(entry.title)) ? byTitle : others).push(hit);
    }));
    return byTitle.concat(others);
}

// Signal strength 0-100 to the Sailfish wlan strength icons.
function wlanIcon(strength) {
    const icons = ["image://theme/icon-m-wlan-0", "image://theme/icon-m-wlan-1", "image://theme/icon-m-wlan-2", "image://theme/icon-m-wlan-3"];
    const s = Math.max(0, Math.min(100, strength || 0));
    return icons[s <= 0 ? 0 : s <= 33 ? 1 : s <= 66 ? 2 : 3];
}

function signalQuality(strength) {
    return strength >= 75 ? qsTr("Excellent") : strength >= 50 ? qsTr("Good") : strength >= 25 ? qsTr("Fair") : qsTr("Weak");
}

function signalText(strength) {
    return strength >= 75 ? qsTr("Excellent signal") : strength >= 50 ? qsTr("Good signal") : strength >= 25 ? qsTr("Fair signal") : qsTr("Weak signal");
}

// "Saved · Secured · Good signal".
function networkSubtitle(network) {
    const parts = network.known ? [qsTr("Saved")] : [];
    const secured = network.secured || (network.security || "Open") !== "Open";
    parts.push(secured ? qsTr("Secured") : qsTr("Open"));
    parts.push(signalText(network.strength || 0));
    return parts.join(" · ");
}

// Bluetooth device icon or type names (as BlueZ and the old pages used them) to theme icons.
function deviceIcon(kind) {
    const icons = {
        headphones: "image://theme/icon-m-headphone",
        headset: "image://theme/icon-m-headphone",
        keyboard: "image://theme/icon-m-keyboard",
        mouse: "image://theme/icon-m-mouse",
        phone: "image://theme/icon-m-phone",
        smartphone: "image://theme/icon-m-phone",
        computer: "image://theme/icon-m-computer",
        laptop: "image://theme/icon-m-computer",
        monitor: "image://theme/icon-m-computer",
        speaker: "image://theme/icon-m-speaker",
        "volume-2": "image://theme/icon-m-speaker"
    };
    return icons[String(kind || "").trim().toLowerCase()] || "image://theme/icon-m-bluetooth";
}

function deviceName(device) {
    return device.alias || device.name || device.address || "";
}

function bluetoothSummary(enabled, devices) {
    if (!enabled)
        return qsTr("Off");
    const connected = (devices || []).find(d => d && d.connected);
    return connected ? deviceName(connected) : qsTr("On");
}

function wifiSummary(enabled, connected, ssid) {
    if (connected)
        return ssid || qsTr("Connected");
    return enabled ? qsTr("On") : qsTr("Off");
}

function batterySummary(level, charging) {
    if (typeof level !== "number" || level < 0)
        return "";
    return charging ? qsTr("%1% · charging").arg(level) : qsTr("%1%").arg(level);
}

function batteryStatus(charging, pluggedIn, secondsLeft) {
    if (charging)
        return qsTr("Charging");
    if (pluggedIn)
        return qsTr("Plugged in, not charging");
    if (!(secondsLeft > 0))
        return qsTr("Discharging");
    const hours = Math.floor(secondsLeft / 3600);
    const minutes = Math.floor(secondsLeft % 3600 / 60);
    return hours > 0 ? qsTr("%1 h %2 min left").arg(hours).arg(minutes) : qsTr("%1 min left").arg(minutes);
}

function percent(fraction) {
    return Math.round(Math.max(0, Math.min(1, fraction || 0)) * 100);
}

// "Europe/Isle_of_Man" -> "Isle of Man".
function zoneCity(zone) {
    return String(zone || "UTC").split("/").pop().replace(/_/g, " ");
}

// Adds or removes id, returning a new list.
function setMember(list, id, member) {
    const rest = (list || []).filter(x => x !== id);
    return member ? rest.concat([id]) : rest;
}

const tiles = [
    { id: "wifi", label: qsTr("Wi-Fi"), desc: qsTr("Toggle wireless network") },
    { id: "cellular", label: qsTr("Mobile data"), desc: qsTr("Toggle cellular data"), needs: "modem" },
    { id: "bluetooth", label: qsTr("Bluetooth"), desc: qsTr("Connect to devices") },
    { id: "airplane", label: qsTr("Airplane mode"), desc: qsTr("Disable all radios") },
    { id: "dnd", label: qsTr("Do not disturb"), desc: qsTr("Silence notifications and calls") },
    { id: "torch", label: qsTr("Torch"), desc: qsTr("Toggle flashlight"), needs: "torch" },
    { id: "location", label: qsTr("Location"), desc: qsTr("GPS and location services") },
    { id: "hotspot", label: qsTr("Hotspot"), desc: qsTr("Share internet connection") },
    { id: "nightlight", label: qsTr("Night light"), desc: qsTr("Reduce blue light") },
    { id: "rotation", label: qsTr("Rotation lock"), desc: qsTr("Lock screen orientation"), needs: "rotation" },
    { id: "autobrightness", label: qsTr("Auto-brightness"), desc: qsTr("Automatic brightness adjustment"), needs: "lightSensor" },
    { id: "lowpower", label: qsTr("Battery saver"), desc: qsTr("Low power mode") },
    { id: "vibration", label: qsTr("Vibration"), desc: qsTr("Haptic feedback"), needs: "vibrator" },
    { id: "power", label: qsTr("Power menu"), desc: qsTr("Show power options") }
];

const defaultTiles = tiles.map(t => t.id);

// Tiles whose hardware is present; hardware maps a tile's needs to a bool.
function presentTiles(hardware) {
    return tiles.filter(t => !t.needs || hardware[t.needs]);
}

const scales = [
    { factor: 0.75, title: qsTr("75%"), description: qsTr("Compact") },
    { factor: 0.9, title: qsTr("90%"), description: qsTr("Small") },
    { factor: 1, title: qsTr("100%"), description: qsTr("Default") },
    { factor: 1.1, title: qsTr("110%"), description: qsTr("Comfortable") },
    { factor: 1.25, title: qsTr("125%"), description: qsTr("Large") },
    { factor: 1.4, title: qsTr("140%"), description: qsTr("Extra large") },
    { factor: 1.5, title: qsTr("150%"), description: qsTr("Huge") }
];

// The shell's screenTimeout is in milliseconds; 0 keeps the screen on.
const screenTimeouts = [
    { ms: 30000, title: qsTr("30 seconds") },
    { ms: 60000, title: qsTr("1 minute") },
    { ms: 120000, title: qsTr("2 minutes") },
    { ms: 300000, title: qsTr("5 minutes") },
    { ms: 0, title: qsTr("Never") }
];

// Index of the option closest to value, so a stored 1.0999 still selects 110%.
function nearestIndex(values, value) {
    let best = 0;
    for (let i = 1; i < values.length; i++) {
        if (Math.abs(values[i] - value) < Math.abs(values[best] - value))
            best = i;
    }
    return best;
}

const handlers = [
    { section: qsTr("Communication"), id: "browser", title: qsTr("Browser") },
    { section: qsTr("Communication"), id: "dialer", title: qsTr("Phone") },
    { section: qsTr("Communication"), id: "messaging", title: qsTr("Messaging") },
    { section: qsTr("Communication"), id: "email", title: qsTr("Email") },
    { section: qsTr("Media"), id: "camera", title: qsTr("Camera") },
    { section: qsTr("Media"), id: "gallery", title: qsTr("Gallery") },
    { section: qsTr("Media"), id: "music", title: qsTr("Music") },
    { section: qsTr("Media"), id: "video", title: qsTr("Video") },
    { section: qsTr("Utilities"), id: "files", title: qsTr("File manager") }
];

// Seconds after the screen turns off during which a swipe unlocks without the PIN.
function lockDelayOptions() {
    return [
        { seconds: 0, label: qsTr("Immediately") },
        { seconds: 5, label: qsTr("5 seconds") },
        { seconds: 30, label: qsTr("30 seconds") },
        { seconds: 60, label: qsTr("1 minute") },
        { seconds: 300, label: qsTr("5 minutes") }
    ];
}

// ModemManager mode mask (2G = 2, 3G = 4, 4G = 8, 5G = 16) -> "4G, 3G and 2G".
function networkModeTitle(mask) {
    const names = [[16, "5G"], [8, "4G"], [4, "3G"], [2, "2G"]].filter(m => mask & m[0]).map(m => m[1]);
    if (names.length === 0)
        return qsTr("Any");
    if (names.length === 1)
        return qsTr("%1 only").arg(names[0]);
    return qsTr("%1 and %2").arg(names.slice(0, -1).join(", ")).arg(names[names.length - 1]);
}

// Security.dataEncryption: "pin", "open", "off" or "none" (docs/ENCRYPTION.md).
function dataEncryptionValue(state) {
    return state === "pin" ? qsTr("Locked by PIN") : state === "open" ? qsTr("Encrypted, not locked") : qsTr("Not encrypted");
}

function dataEncryptionNote(state) {
    if (state === "pin")
        return qsTr("Your phone asks for the quick PIN when it starts, before anything on it can be read. A PIN only slows down someone who copies the storage: with a fast computer a 6-digit PIN can be guessed within hours to days.");
    if (state === "open")
        return qsTr("Your data is encrypted, but your phone opens it at startup without asking. Set a quick PIN to lock it.");
    if (state === "off")
        return qsTr("This phone was set up before Marathon encrypted its data. Erase all content to start again with encryption.");
    return qsTr("Marathon doesn't encrypt data on this phone yet.");
}

// Android apps: the runtime's state, its permission groups and special access.
function androidState(state) {
    switch (state) {
    case "running":
        return qsTr("Running");
    case "starting":
        return qsTr("Starting");
    case "stopping":
        return qsTr("Stopping");
    }
    return qsTr("Stopped");
}

// Powers of 1000 with kB, MB and GB, as Android and the Store count.
function dataSize(bytes) {
    return Qt.locale().formattedDataSize(Math.max(0, bytes || 0), 1, 3);
}

function duration(seconds) {
    const s = Math.max(0, Math.floor(seconds || 0));
    if (s < 60)
        return qsTr("Less than a minute");
    if (s < 3600)
        return qsTr("%n minutes", "", Math.floor(s / 60));
    if (s < 86400)
        return qsTr("%n hours", "", Math.floor(s / 3600));
    return qsTr("%n days", "", Math.floor(s / 86400));
}

// The permissions App permissions lists, in order: Marathon's vocabulary
// (Permissions.describe) without its restricted ones, Android apps' first
// (deckardd's PermissionMap uses the same names).
const permissionNames = ["location", "camera", "microphone", "contacts", "calendar", "storage", "notifications", "telephony", "sms", "bluetooth", "sensors", "network", "alarms", "secret-service"];

const androidAccess = [
    { kind: "all_files", title: qsTr("All files"), description: qsTr("Read and change all your files") },
    { kind: "install_apps", title: qsTr("Install other apps"), description: qsTr("Install apps, as app stores do") },
    { kind: "alarms", title: qsTr("Alarms and reminders"), description: qsTr("Wake the phone at an exact time") },
    { kind: "battery", title: qsTr("Unrestricted battery"), description: qsTr("Run in the background without limits") },
    { kind: "notification_listener", title: qsTr("Notification access"), description: qsTr("Read every notification and act on it") },
    { kind: "dnd", title: qsTr("Do not disturb access"), description: qsTr("Turn Do not disturb on and off") },
    { kind: "usage", title: qsTr("Usage access"), description: qsTr("See which apps you use and how often") },
    { kind: "write_settings", title: qsTr("Change system settings"), description: qsTr("Change settings like brightness") },
    { kind: "overlay", title: qsTr("Display over other apps"), description: qsTr("Draw on top of other Android apps") },
    { kind: "pip", title: qsTr("Picture in picture"), description: qsTr("Keep playing video in a small window") },
    { kind: "accessibility", title: qsTr("Accessibility"), description: qsTr("See the screen and act for you") },
    { kind: "device_admin", title: qsTr("Device admin"), description: qsTr("Lock the phone and set security rules") }
];

function androidAccessKind(kind) {
    return androidAccess.find(a => a.kind === kind) || { kind: kind, title: kind, description: "" };
}

// MMS carrier settings (mmsd-tng). Its placeholders for "not set".
function mmsValue(value) {
    const v = String(value || "");
    return v === "http://mms.invalid" || v === "apn.invalid" || v === "NULL" ? "" : v;
}

const hostPattern = /^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$/;

function validPort(text) {
    return /^[0-9]{1,5}$/.test(text) && Number(text) >= 1 && Number(text) <= 65535;
}

// "" when the MMSC is a usable http or https address.
function mmscError(text) {
    const t = String(text || "").trim();
    if (t === "")
        return qsTr("Enter the MMSC address");
    const m = /^https?:\/\/([^/:?#]+)(:([0-9]+))?([/?#].*)?$/.exec(t);
    if (!m || /\s/.test(t) || !hostPattern.test(m[1]) || (m[3] !== undefined && !validPort(m[3])))
        return qsTr("Enter an address starting with http:// or https://");
    if (mmsValue(t) === "")
        return qsTr("Enter your carrier's MMSC address");
    return "";
}

// "" when empty or a host with an optional port.
function mmsProxyError(text) {
    const t = String(text || "").trim();
    if (t === "")
        return "";
    const m = /^([^:]+)(:([0-9]+))?$/.exec(t);
    if (!m || !hostPattern.test(m[1]) || (m[3] !== undefined && !validPort(m[3])))
        return qsTr("Enter a host name or address, with a port if needed, like 10.0.0.1:8080");
    return "";
}

function apnError(text) {
    const t = String(text || "").trim();
    if (t === "")
        return qsTr("Enter the MMS APN");
    if (t.length > 100 || !/^[A-Za-z0-9]([A-Za-z0-9._-]*[A-Za-z0-9])?$/.test(t))
        return qsTr("Use letters, digits, dots and hyphens only");
    if (mmsValue(t) === "")
        return qsTr("Enter your carrier's MMS APN");
    return "";
}

// Android refuses to remove its own Deckard packages.
function androidRemovable(pkg) {
    return String(pkg || "").indexOf("org.marathonos.deckard.") !== 0;
}
