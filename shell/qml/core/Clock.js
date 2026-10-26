.pragma library

// Clock times for the status bar, notifications, clipboard and weather: the
// 12/24-hour setting decides, the locale supplies the AM/PM text and any
// 12-hour pattern of its own.

// Locale.ShortFormat; the Locale enum is not visible to a library.
const SHORT_FORMAT = 1;

function twelveHour(setting) {
    return setting !== "24h";
}

function pattern(setting, locale) {
    if (!twelveHour(setting))
        return "HH:mm";
    const own = locale.timeFormat(SHORT_FORMAT);
    return /ap/i.test(own) ? own : "h:mm AP";
}

function format(date, setting, locale) {
    const loc = locale || Qt.locale();
    return date.toLocaleTimeString(loc, pattern(setting, loc));
}
