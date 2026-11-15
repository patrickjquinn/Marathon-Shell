// SPDX-FileCopyrightText: 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-browser apps/wpe/WPEWebPage.cpp)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
//
// Script text entry, from Atlantic's dispatchTextToFocusedElement() and
// dispatchBackspaceToFocusedElement() (atlantic-browser c150119). Used only
// when WebView.inputMode is WebView.ScriptInput: Atlantic types keyboard text
// into the focused field from script, and Pacific keeps that path as the
// fallback for the day-1 comparison with WebKit's native input-method
// context (the default). Isolated script world.
(function() {
    if (window.__pacificIme) return;

    function isEditable(e) {
        if (!e) return false;
        if (e.isContentEditable) return true;
        var tag = (e.tagName || '').toLowerCase();
        if (tag === 'textarea') return !e.readOnly && !e.disabled;
        if (tag === 'input') {
            var t = (e.type || 'text').toLowerCase();
            var blocked = {button:1,submit:1,reset:1,checkbox:1,radio:1,file:1,image:1,range:1,color:1,hidden:1};
            return !blocked[t] && !e.readOnly && !e.disabled;
        }
        return false;
    }
    function deepActive(doc) {
        var a = doc && doc.activeElement;
        for (var i = 0; a && i < 16; i++) {
            var tg = a.tagName;
            if (tg === 'IFRAME' || tg === 'FRAME') {
                try { var d = a.contentDocument; if (!d) return null; a = d.activeElement; continue; } catch (_e) { return null; }
            }
            if (a.shadowRoot && a.shadowRoot.activeElement) { a = a.shadowRoot.activeElement; continue; }
            break;
        }
        return a;
    }
    // composed:true, or a component keeping its <input> in a shadow root never
    // tells its form the field has a value (Atlantic: reddit's login button
    // stayed disabled).
    function fireInput(el, data, inputType) {
        try {
            if (typeof InputEvent === 'function')
                el.dispatchEvent(new InputEvent('input', { bubbles: true, composed: true, data: data, inputType: inputType }));
            else
                el.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        } catch (_e) {
            el.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
        }
    }

    var imeTarget = null;
    var imeSeq = 0;
    var tokens = new WeakMap();

    // Inserts t at the caret, first removing replaceBefore characters before
    // it (the previous preedit). A composition is bound to the element it
    // started in: once focus moved, its tail is dropped instead of landing in
    // the new field (Atlantic: a username's last letters in the password).
    function insert(t, replaceBefore) {
        replaceBefore = replaceBefore | 0;
        var el = deepActive(document);
        if (!isEditable(el)) return false;
        if (replaceBefore > 0) {
            if (!imeTarget || tokens.get(el) !== imeTarget) return false;
        } else {
            imeTarget = ++imeSeq;
            tokens.set(el, imeTarget);
        }
        var doc = el.ownerDocument || document;
        var win = doc.defaultView || window;
        if (el.isContentEditable) {
            var sel = win.getSelection();
            if (!sel || !sel.rangeCount) return false;
            if (doc.queryCommandSupported && doc.queryCommandSupported('insertText')) {
                for (var i = 0; i < replaceBefore; i++) doc.execCommand('delete', false, null);
                if (t.length) doc.execCommand('insertText', false, t);
                return true;
            }
            var r = sel.getRangeAt(0);
            if (r.collapsed && replaceBefore > 0) {
                var available = Math.min(replaceBefore, r.startOffset);
                if (available > 0) r.setStart(r.startContainer, r.startOffset - available);
            }
            r.deleteContents();
            if (t.length) {
                var node = doc.createTextNode(t);
                r.insertNode(node);
                r.setStartAfter(node);
            }
            r.collapse(true);
            sel.removeAllRanges();
            sel.addRange(r);
            fireInput(el, t, t.length ? 'insertText' : 'deleteContentBackward');
            return true;
        }
        var start = el.selectionStart;
        var end = el.selectionEnd;
        if (start === end && replaceBefore > 0) start = Math.max(0, start - replaceBefore);
        if (typeof start === 'number' && typeof end === 'number' && typeof el.setRangeText === 'function') {
            el.setRangeText(t, start, end, 'end');
        } else if (typeof start === 'number' && typeof end === 'number') {
            var v = el.value || '';
            el.value = v.slice(0, start) + t + v.slice(end);
            var p = start + t.length;
            if (el.setSelectionRange) el.setSelectionRange(p, p);
        } else {
            var vv = el.value || '';
            if (replaceBefore > 0 && vv.length) vv = vv.slice(0, Math.max(0, vv.length - replaceBefore));
            el.value = vv + t;
        }
        fireInput(el, t, t.length ? 'insertText' : 'deleteContentBackward');
        return true;
    }

    function backspace() {
        var el = deepActive(document);
        if (!isEditable(el)) return false;
        var doc = el.ownerDocument || document;
        var win = doc.defaultView || window;
        if (el.isContentEditable) {
            if (doc.queryCommandSupported && doc.queryCommandSupported('delete')) {
                doc.execCommand('delete', false, null);
                return true;
            }
            var sel = win.getSelection();
            if (!sel || !sel.rangeCount) return false;
            var r = sel.getRangeAt(0);
            if (r.collapsed) {
                if (r.startOffset <= 0) return true;
                r.setStart(r.startContainer, r.startOffset - 1);
            }
            r.deleteContents();
            fireInput(el, null, 'deleteContentBackward');
            return true;
        }
        var start = el.selectionStart;
        var end = el.selectionEnd;
        var v = el.value || '';
        if (typeof start === 'number' && typeof end === 'number') {
            if (start !== end) {
                el.value = v.slice(0, start) + v.slice(end);
            } else if (start > 0) {
                el.value = v.slice(0, start - 1) + v.slice(end);
                start -= 1;
            }
            if (el.setSelectionRange) el.setSelectionRange(start, start);
        } else if (v.length) {
            el.value = v.slice(0, -1);
        }
        fireInput(el, null, 'deleteContentBackward');
        return true;
    }

    window.__pacificIme = { insert: insert, backspace: backspace };
})();
