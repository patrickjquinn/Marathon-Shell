pragma Singleton
import QtQuick

// Display grouping and loose matching for phone numbers; never rewrites the stored number.
QtObject {
    id: root

    readonly property var twoDigitCountryCodes: ["20", "27", "30", "31", "32", "33", "34", "36", "39", "40", "41", "43", "44", "45", "46", "47", "48", "49", "51", "52", "53", "54", "55", "56", "57", "58", "60", "61", "62", "63", "64", "65", "66", "81", "82", "84", "86", "90", "91", "92", "93", "94", "95", "98"]

    function digits(number) {
        return String(number || "").replace(/\D/g, "");
    }

    function group(d) {
        var out = [];
        while (d.length > 4) {
            out.push(d.slice(0, 3));
            d = d.slice(3);
        }
        if (d.length > 0)
            out.push(d);
        return out.join(" ");
    }

    function format(number) {
        var raw = String(number || "").trim();
        if (/[*#,;pPwW]/.test(raw))
            return raw;
        var d = digits(raw);
        if (d.length === 0)
            return raw.charAt(0) === "+" ? "+" : "";
        if (raw.charAt(0) !== "+")
            return group(d);
        var ccLength = (d.charAt(0) === "1" || d.charAt(0) === "7") ? 1 : twoDigitCountryCodes.indexOf(d.slice(0, 2)) !== -1 ? 2 : 3;
        var cc = d.slice(0, ccLength);
        var rest = d.slice(ccLength);
        return "+" + cc + (rest.length > 0 ? " " + group(rest) : "");
    }

    // Trailing 9 digits drop trunk/country prefixes: "+1 555 123 4567" == "5551234567".
    function sameNumber(a, b) {
        var x = digits(a);
        var y = digits(b);
        if (x.length === 0 || y.length === 0)
            return false;
        if (x.length < 9 || y.length < 9)
            return x === y;
        return x.slice(-9) === y.slice(-9);
    }
}
