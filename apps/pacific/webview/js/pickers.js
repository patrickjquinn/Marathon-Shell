// SPDX-FileCopyrightText: 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-browser apps/wpe)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
//
// Form pickers, from Atlantic's kInputPickerBridge and kSelectBridge and the
// resolve code in WPEWebPage.cpp (atlantic-browser c150119). Runs in Pacific's
// isolated script world.
//
// <input type=date|month|week|time|datetime-local|color>: WPE has no native
// picker (its PageClient returns no colour or date/time picker), so the
// activation is intercepted and handed to the UI (pacificPicker), which shows
// a Silica picker and answers through __pacificPickers.resolveInput(value).
//
// <select>: the view uses WebKit's native option menu (show-option-menu) by
// default. With scriptSelectMenus on (a fallback in case the native menu does
// not open on the device), the activation is intercepted here instead and
// reported as pacificSelect; __pacificPickers.resolveSelect(index) answers.
(function() {
    if (window.__pacificPickers) return;

    var PICKER_TYPES = { date:1, month:1, week:1, time:1, 'datetime-local':1, color:1 };
    var pendingInput = null;
    var pendingSelect = null;

    function closestTag(el, tag) {
        while (el && el.tagName && el.tagName.toLowerCase() !== tag)
            el = el.parentElement;
        return (el && el.tagName && el.tagName.toLowerCase() === tag) ? el : null;
    }

    function rectOf(el) {
        var r = el.getBoundingClientRect();
        return { x: r.left, y: r.top, width: r.width, height: r.height };
    }

    function handleInput(e) {
        var el = closestTag(e.target, 'input');
        if (!el) return;
        // The attribute, not el.type: with the runtime pref off the element
        // reports type=text, and the intent is still a picker.
        var type = (el.getAttribute('type') || '').toLowerCase();
        if (!PICKER_TYPES[type] || el.disabled || el.readOnly) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        if (e.type !== 'click') return; // one report per tap
        pendingInput = el;
        try {
            window.webkit.messageHandlers.pacificPicker.postMessage({
                type: type,
                value: el.value || '',
                min: el.getAttribute('min') || '',
                max: el.getAttribute('max') || '',
                step: el.getAttribute('step') || '',
                rect: rectOf(el)
            });
        } catch (ex) {
            console.error('[pacific-picker] ' + ex);
        }
    }

    function handleSelect(e) {
        if (!window.__pacificScriptSelect) return;
        var el = closestTag(e.target, 'select');
        // Disabled controls stay inert; multi-selects and list boxes need
        // WebKit's own handling.
        if (!el || el.disabled || el.multiple || el.size > 1) return;
        e.preventDefault();
        e.stopImmediatePropagation();
        if (e.type !== 'click') return;
        var opts = [];
        for (var i = 0; i < el.options.length; i++) {
            var o = el.options[i];
            opts.push({ label: o.text, enabled: !o.disabled, group: o.parentElement && o.parentElement.tagName === 'OPTGROUP' ? o.parentElement.label : '' });
        }
        pendingSelect = el;
        try {
            window.webkit.messageHandlers.pacificSelect.postMessage({
                options: opts,
                selectedIndex: el.selectedIndex,
                rect: rectOf(el)
            });
        } catch (ex) {
            console.error('[pacific-select] ' + ex);
        }
    }

    ['mousedown', 'pointerdown', 'click'].forEach(function(type) {
        document.addEventListener(type, handleInput, true);
        document.addEventListener(type, handleSelect, true);
    });
    document.addEventListener('touchstart', handleInput, { capture: true, passive: true });

    function fire(el, names) {
        names.forEach(function(n) { el.dispatchEvent(new Event(n, { bubbles: true, composed: true })); });
    }

    window.__pacificPickers = {
        resolveInput: function(value) {
            var el = pendingInput;
            pendingInput = null;
            if (!el) return false;
            el.value = value;
            fire(el, ['input', 'change']);
            return true;
        },
        cancelInput: function() { pendingInput = null; },
        resolveSelect: function(index) {
            var el = pendingSelect;
            pendingSelect = null;
            if (!el) return false;
            el.selectedIndex = index;
            fire(el, ['input', 'change']);
            return true;
        },
        cancelSelect: function() { pendingSelect = null; }
    };
})();
