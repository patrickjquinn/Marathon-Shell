// SPDX-FileCopyrightText: 2021 - 2026 Jolla Ltd.
// SPDX-License-Identifier: MPL-2.0

// Convert from camelCase to snake_case
// Must exactly match the outputs from generate_property_translations.py _convert_key()
function _convert_key(name, prefix) {
    prefix = (typeof prefix !== "undefined") ? prefix : "sailfish_components_webview_popups-la"
    var snake = name.replace(/([a-z\d]+)([A-Z])/g,"$1_$2").toLowerCase()
    return snake.length ? "%1-%2".arg(prefix).arg(snake) : ""
}

// Convert a gecko key to a translated string via a Qt translation Id
// textBunlde is either a gecko key, or an array containing a key followed by
// input parameters
function geckoKeyToString(textBundle, prefix) {
    var string
    var bundle = (typeof textBundle !== "string")
    var key = bundle ? textBundle[0] : textBundle
    var id = _convert_key(key, prefix)
    string = qsTrId(id)
    if (string === id) {
        // If the key has no translation, use the original gecko key instead
        // since it may be a pre-translated string
        string = key
    }
    if (bundle) {
        for (var input = 1; input < textBundle.length; ++input) {
            string = string.arg(textBundle[input])
        }
    }

    return string
}

// Trim the input to the maximum and add an ellipsis (or local equivalent) if needed
function trimInput(string, maxlen) {
    maxlen = (typeof maxlen !== "undefined") ? maxlen : 150
    if (string.length > maxlen) {
        //: Used for truncating a string; %1 will be replaced with a truncted version of the original string
        //% "%1\u2026"
        string = qsTrId("sailfish_components_webview_popups-st-truncate").arg(string.substring(0, maxlen))
    }
    return string
}
