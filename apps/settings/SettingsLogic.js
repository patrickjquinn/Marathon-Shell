.pragma library

// Route names (deep links, search) to page files under pages/.
const pages = {
    wifi: "WiFiPage.qml",
    bluetooth: "BluetoothPage.qml",
    cellular: "CellularPage.qml",
    display: "DisplayPage.qml",
    scale: "DisplayPage.qml",
    screentimeout: "DisplayPage.qml",
    wallpaper: "WallpaperPage.qml",
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
    accounts: "AccountsPage.qml",
    quicksettings: "QuickSettingsPage.qml",
    hiddenapps: "HiddenAppsPage.qml",
    defaultapps: "DefaultAppsPage.qml",
    appsort: "AppLayoutPage.qml"
};

function pageFile(route) {
    const name = String(route || "").replace(/^\/+/, "").split(/[/?]/)[0].toLowerCase();
    return pages[name] || "";
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
            { page: "wallpaper", title: qsTr("Wallpaper"), icon: "image://theme/icon-m-wallpaper", keywords: "background home screen" },
            { page: "sound", title: qsTr("Sounds"), icon: "image://theme/icon-m-volume", keywords: "volume ringtone alarm audio mute" },
            { page: "notifications", title: qsTr("Notifications"), icon: "image://theme/icon-m-notifications", keywords: "alerts lock screen per-app do not disturb" },
            { page: "datetime", title: qsTr("Date and time"), icon: "image://theme/icon-m-clock", keywords: "time zone timezone clock 24-hour 12-hour format city" },
            { page: "battery", title: qsTr("Battery"), icon: "image://theme/icon-m-battery", keywords: "power saver profile charging" },
            { page: "storage", title: qsTr("Storage"), icon: "image://theme/icon-m-storage", keywords: "disk space memory usage free" },
            { page: "keyboard", title: qsTr("Keyboard"), icon: "image://theme/icon-m-keyboard", keywords: "language autocorrect predictions typing capitalize" }
        ]
    },
    {
        title: qsTr("Privacy"),
        entries: [
            { page: "security", title: qsTr("Security"), icon: "image://theme/icon-m-device-lock", keywords: "pin password lock fingerprint biometric" },
            { page: "accounts", title: qsTr("Accounts"), icon: "image://theme/icon-m-people", keywords: "carddav caldav sync nextcloud contacts calendar" }
        ]
    },
    {
        title: qsTr("Apps"),
        entries: [
            { page: "appmanager", title: qsTr("Installed apps"), icon: "image://theme/icon-m-apps", keywords: "apps uninstall installed remove manager" },
            { page: "defaultapps", title: qsTr("Default apps"), icon: "image://theme/icon-m-favorite", keywords: "browser phone email handler open with" },
            { page: "hiddenapps", title: qsTr("Hidden apps"), icon: "image://theme/icon-m-hidden", keywords: "hide drawer" },
            { page: "appsort", title: qsTr("App grid"), icon: "image://theme/icon-m-app-grid", keywords: "grid columns icons layout filter desktop native search badges" },
            { page: "quicksettings", title: qsTr("Quick settings"), icon: "image://theme/icon-m-toggle", keywords: "tiles shade toggles" }
        ]
    },
    {
        title: qsTr("System"),
        entries: [
            { page: "updates", title: qsTr("Software updates"), icon: "image://theme/icon-m-update", keywords: "upgrade version release channel" },
            { page: "about", title: qsTr("About device"), icon: "image://theme/icon-m-about", keywords: "device name version model kernel build licenses legal terms privacy" },
            { app: "terminal", title: qsTr("Terminal"), icon: "image://theme/icon-m-terminal", keywords: "shell command console" }
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
    const found = [];
    sections.forEach(section => section.entries.forEach(entry => {
        const hay = words(entry.title + " " + section.title + " " + entry.keywords);
        if (wanted.every(w => hay.some(h => h.indexOf(w) === 0)))
            found.push(Object.assign({ section: section.title }, entry));
    }));
    return found;
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

const defaultTiles = ["wifi", "bluetooth", "flight", "cellular", "rotation", "autobrightness", "location", "hotspot", "vibration", "nightlight", "torch", "notifications", "battery", "screenshot", "settings", "lock"];

const tiles = [
    { id: "wifi", label: qsTr("Wi-Fi"), desc: qsTr("Toggle wireless network") },
    { id: "bluetooth", label: qsTr("Bluetooth"), desc: qsTr("Connect to devices") },
    { id: "flight", label: qsTr("Flight mode"), desc: qsTr("Disable all radios") },
    { id: "cellular", label: qsTr("Mobile network"), desc: qsTr("Toggle cellular data") },
    { id: "rotation", label: qsTr("Rotation lock"), desc: qsTr("Lock screen orientation") },
    { id: "autobrightness", label: qsTr("Auto-brightness"), desc: qsTr("Automatic brightness adjustment") },
    { id: "location", label: qsTr("Location"), desc: qsTr("GPS and location services") },
    { id: "hotspot", label: qsTr("Hotspot"), desc: qsTr("Share internet connection") },
    { id: "vibration", label: qsTr("Vibration"), desc: qsTr("Haptic feedback") },
    { id: "nightlight", label: qsTr("Night light"), desc: qsTr("Reduce blue light") },
    { id: "torch", label: qsTr("Torch"), desc: qsTr("Toggle flashlight") },
    { id: "notifications", label: qsTr("Do not disturb"), desc: qsTr("Silence notifications and calls") },
    { id: "battery", label: qsTr("Battery saver"), desc: qsTr("Low power mode") },
    { id: "screenshot", label: qsTr("Screenshot"), desc: qsTr("Capture screen") },
    { id: "settings", label: qsTr("Settings"), desc: qsTr("Open Settings") },
    { id: "lock", label: qsTr("Lock device"), desc: qsTr("Lock the screen") },
    { id: "power", label: qsTr("Power menu"), desc: qsTr("Show power options") }
];

const scales = [
    { factor: 0.75, title: qsTr("75%"), description: qsTr("Compact") },
    { factor: 0.9, title: qsTr("90%"), description: qsTr("Small") },
    { factor: 1, title: qsTr("100%"), description: qsTr("Default") },
    { factor: 1.1, title: qsTr("110%"), description: qsTr("Comfortable") },
    { factor: 1.25, title: qsTr("125%"), description: qsTr("Large") },
    { factor: 1.4, title: qsTr("140%"), description: qsTr("Extra large") },
    { factor: 1.5, title: qsTr("150%"), description: qsTr("Huge") }
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
