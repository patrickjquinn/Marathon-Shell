// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Page access for Pilot (Keel Actions / MCP: page.read, page.links,
// page.click, page.fill, page.submit, "browse for me"). Runs in Pacific's
// isolated script world: the page shares the DOM but cannot see these
// functions, the element ids or the WeakMap behind them, and cannot replace
// them. Called by WebView.agent*() through evaluate-in-world; every result is
// plain JSON and bounded in size.
(function() {
    if (window.__pacificAgent) return;

    var INTERACTIVE = 'a[href],area[href],button,input,select,textarea,summary,details,label[for],' +
        '[contenteditable=""],[contenteditable="true"],[tabindex]:not([tabindex="-1"]),' +
        '[role=button],[role=link],[role=checkbox],[role=radio],[role=switch],[role=tab],[role=menuitem],' +
        '[role=menuitemcheckbox],[role=menuitemradio],[role=option],[role=combobox],[role=textbox],' +
        '[role=searchbox],[role=slider],[role=spinbutton],[role=treeitem],[onclick]';
    var MAX_LABEL = 120;
    var MAX_VALUE = 200;

    var nextId = 1;
    var idOf = new WeakMap();
    var byId = new Map();

    function idFor(el) {
        var id = idOf.get(el);
        if (!id) {
            id = 'e' + (nextId++);
            idOf.set(el, id);
        }
        byId.set(id, typeof WeakRef === 'function' ? new WeakRef(el) : { deref: function() { return el; } });
        return id;
    }

    function resolve(id) {
        var ref = byId.get(String(id));
        var el = ref ? ref.deref() : null;
        if (!el || !el.isConnected) {
            byId.delete(String(id));
            return null;
        }
        return el;
    }

    function clip(s, n) {
        s = (s == null ? '' : String(s)).replace(/\s+/g, ' ').trim();
        return s.length > n ? s.slice(0, n - 1) + '…' : s;
    }

    function textOf(el) {
        try { return el.innerText || el.textContent || ''; } catch (e) { return ''; }
    }

    function labelOf(el) {
        var v = el.getAttribute('aria-label');
        if (v) return clip(v, MAX_LABEL);
        var by = el.getAttribute('aria-labelledby');
        if (by) {
            var parts = by.split(/\s+/).map(function(i) {
                var n = (el.getRootNode && el.getRootNode().getElementById) ? el.getRootNode().getElementById(i) : document.getElementById(i);
                return n ? textOf(n) : '';
            });
            v = parts.join(' ');
            if (v.trim()) return clip(v, MAX_LABEL);
        }
        if (el.labels && el.labels.length) {
            v = Array.prototype.map.call(el.labels, textOf).join(' ');
            if (v.trim()) return clip(v, MAX_LABEL);
        }
        var tag = el.tagName.toLowerCase();
        if (tag === 'input') {
            var t = (el.type || '').toLowerCase();
            if ((t === 'submit' || t === 'button' || t === 'reset') && el.value) return clip(el.value, MAX_LABEL);
            if (t === 'image' && el.alt) return clip(el.alt, MAX_LABEL);
        }
        v = el.getAttribute('placeholder') || '';
        if (v) return clip(v, MAX_LABEL);
        v = clip(textOf(el), MAX_LABEL);
        if (v) return v;
        var img = el.querySelector && el.querySelector('img[alt]');
        if (img && img.alt) return clip(img.alt, MAX_LABEL);
        v = el.getAttribute('title') || el.getAttribute('name') || '';
        return clip(v, MAX_LABEL);
    }

    function roleOf(el) {
        var r = el.getAttribute('role');
        if (r) return r;
        var tag = el.tagName.toLowerCase();
        switch (tag) {
        case 'a': case 'area': return 'link';
        case 'button': case 'summary': return 'button';
        case 'select': return el.multiple ? 'listbox' : 'combobox';
        case 'textarea': return 'textbox';
        case 'input':
            switch ((el.type || 'text').toLowerCase()) {
            case 'button': case 'submit': case 'reset': case 'image': return 'button';
            case 'checkbox': return 'checkbox';
            case 'radio': return 'radio';
            case 'range': return 'slider';
            case 'number': return 'spinbutton';
            case 'search': return 'searchbox';
            case 'hidden': return 'hidden';
            default: return 'textbox';
            }
        }
        if (el.isContentEditable) return 'textbox';
        return 'generic';
    }

    function visibleBox(el, offset) {
        var r = el.getBoundingClientRect();
        var box = [Math.round(r.left + offset.x), Math.round(r.top + offset.y), Math.round(r.width), Math.round(r.height)];
        var visible = r.width > 0 && r.height > 0;
        if (visible) {
            var cs = getComputedStyle(el);
            visible = cs.visibility !== 'hidden' && cs.display !== 'none' && parseFloat(cs.opacity || '1') > 0.05;
        }
        var vw = window.innerWidth, vh = window.innerHeight;
        var inViewport = visible && box[0] < vw && box[1] < vh && box[0] + box[2] > 0 && box[1] + box[3] > 0;
        return { box: box, visible: visible, inViewport: inViewport };
    }

    function describe(el, offset) {
        var tag = el.tagName.toLowerCase();
        var geo = visibleBox(el, offset);
        var d = {
            id: idFor(el),
            tag: tag,
            role: roleOf(el),
            label: labelOf(el),
            visible: geo.visible,
            inViewport: geo.inViewport,
            box: geo.box
        };
        if (tag === 'a' || tag === 'area') d.href = el.href;
        if (tag === 'input' || tag === 'textarea' || tag === 'select') {
            d.name = el.name || '';
            if (tag === 'input') d.type = (el.type || 'text').toLowerCase();
            if (d.type === 'checkbox' || d.type === 'radio') d.checked = !!el.checked;
            else if (d.type === 'password') d.value = el.value ? '•••' : '';
            else if (tag !== 'select') d.value = clip(el.value, MAX_VALUE);
            if (el.required) d.required = true;
            if (el.readOnly) d.readOnly = true;
            var ac = el.getAttribute('autocomplete');
            if (ac) d.autocomplete = ac;
        }
        if (tag === 'select') {
            d.value = el.value;
            d.options = Array.prototype.slice.call(el.options, 0, 30).map(function(o) {
                return { value: o.value, label: clip(o.text, 60), selected: o.selected };
            });
            if (el.options.length > 30) d.moreOptions = el.options.length - 30;
        }
        if (el.isContentEditable && tag !== 'input' && tag !== 'textarea') {
            d.value = clip(textOf(el), MAX_VALUE);
            d.editable = true;
        }
        if (el.disabled || el.getAttribute('aria-disabled') === 'true') d.disabled = true;
        if (el.getAttribute('aria-expanded')) d.expanded = el.getAttribute('aria-expanded') === 'true';
        if (el.form) d.form = idFor(el.form);
        return d;
    }

    // Document order walk over the document, open shadow roots and
    // same-origin frames (with their offset); cross-origin frames are listed
    // but not entered.
    function collect(root, offset, out, frames, depth) {
        if (depth > 6) return;
        var nodes;
        try { nodes = root.querySelectorAll('*'); } catch (e) { return; }
        for (var i = 0; i < nodes.length; i++) {
            var el = nodes[i];
            if (el.shadowRoot) collect(el.shadowRoot, offset, out, frames, depth + 1);
            var tag = el.tagName;
            if (tag === 'IFRAME' || tag === 'FRAME') {
                var fr = el.getBoundingClientRect();
                var inner = null;
                try { inner = el.contentDocument; } catch (e) { inner = null; }
                if (inner)
                    collect(inner, { x: offset.x + fr.left, y: offset.y + fr.top }, out, frames, depth + 1);
                else
                    frames.push({ src: el.src, box: [Math.round(fr.left + offset.x), Math.round(fr.top + offset.y), Math.round(fr.width), Math.round(fr.height)] });
                continue;
            }
            var matches = false;
            try { matches = el.matches(INTERACTIVE); } catch (e) { matches = false; }
            if (!matches) continue;
            if (tag === 'INPUT' && (el.type || '').toLowerCase() === 'hidden') continue;
            out.push({ el: el, offset: offset });
        }
    }

    function snapshot(opts) {
        opts = opts || {};
        var limit = Math.max(1, Math.min(opts.limit || 300, 2000));
        var found = [];
        var frames = [];
        collect(document, { x: 0, y: 0 }, found, frames, 0);
        var described = found.map(function(f, index) {
            var d = describe(f.el, f.offset);
            d._order = index;
            return d;
        });
        if (!opts.includeHidden)
            described = described.filter(function(d) { return d.visible; });
        var total = described.length;
        // Bounded: on-screen first, then the rest in document order.
        described.sort(function(a, b) {
            if (a.inViewport !== b.inViewport) return a.inViewport ? -1 : 1;
            return a._order - b._order;
        });
        described = described.slice(0, limit).sort(function(a, b) { return a._order - b._order; });
        described.forEach(function(d) { delete d._order; });
        var forms = Array.prototype.slice.call(document.forms, 0, 20).map(function(f) {
            return { id: idFor(f), action: f.action, method: (f.method || 'get').toLowerCase(), name: f.getAttribute('name') || '', label: labelOf(f) };
        });
        var result = {
            url: location.href,
            title: document.title,
            lang: document.documentElement.lang || '',
            viewport: { width: window.innerWidth, height: window.innerHeight, scrollX: Math.round(window.scrollX),
                scrollY: Math.round(window.scrollY), scrollHeight: document.documentElement.scrollHeight },
            elements: described,
            forms: forms,
            frames: frames.slice(0, 20),
            total: total,
            truncated: total > described.length
        };
        if (opts.text)
            result.text = visibleText(opts.text === true ? 4000 : opts.text);
        return result;
    }

    function visibleText(max) {
        max = Math.max(100, Math.min(max || 20000, 200000));
        var t = '';
        try { t = document.body ? document.body.innerText : ''; } catch (e) { t = ''; }
        t = t.replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n');
        return t.length > max ? t.slice(0, max) : t;
    }

    function html(max) {
        max = Math.max(1000, Math.min(max || 2000000, 10000000));
        var h = document.documentElement ? document.documentElement.outerHTML : '';
        return h.length > max ? h.slice(0, max) : h;
    }

    // Scrolls the element into view and returns its box in viewport CSS px,
    // for a native (trusted) tap by the view.
    function locate(id) {
        var el = resolve(id);
        if (!el) return { ok: false, error: 'unknown or detached element ' + id };
        try { el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' }); } catch (e) { el.scrollIntoView(); }
        var r = el.getBoundingClientRect();
        // Offset of the element's frame chain, for same-origin frames.
        var x = r.left, y = r.top;
        var win = el.ownerDocument.defaultView;
        while (win && win !== window && win.frameElement) {
            var fr = win.frameElement.getBoundingClientRect();
            x += fr.left;
            y += fr.top;
            win = win.parent;
        }
        var cx = x + r.width / 2, cy = y + r.height / 2;
        var top = document.elementFromPoint(cx, cy);
        var covered = !!top && top !== el && !el.contains(top) && !(top.shadowRoot && top.contains(el));
        return { ok: true, box: [x, y, r.width, r.height], center: [cx, cy], covered: covered };
    }

    function click(id) {
        var el = resolve(id);
        if (!el) return { ok: false, error: 'unknown or detached element ' + id };
        var l = locate(id);
        var opts = { bubbles: true, cancelable: true, composed: true, clientX: l.center[0], clientY: l.center[1], view: window };
        try {
            el.dispatchEvent(new PointerEvent('pointerdown', opts));
            el.dispatchEvent(new MouseEvent('mousedown', opts));
            el.dispatchEvent(new PointerEvent('pointerup', opts));
            el.dispatchEvent(new MouseEvent('mouseup', opts));
        } catch (e) {}
        el.click();
        return { ok: true };
    }

    function focus(id) {
        var el = resolve(id);
        if (!el) return { ok: false, error: 'unknown or detached element ' + id };
        locate(id);
        el.focus({ preventScroll: true });
        return { ok: true, focused: el.ownerDocument.activeElement === el };
    }

    function fire(el, names) {
        names.forEach(function(n) { el.dispatchEvent(new Event(n, { bubbles: true, composed: true })); });
    }

    // Sets a value through the prototype's setter (what frameworks such as
    // React observe), then fires input and change.
    function setValue(id, value) {
        var el = resolve(id);
        if (!el) return { ok: false, error: 'unknown or detached element ' + id };
        var tag = el.tagName.toLowerCase();
        if (el.disabled || el.readOnly) return { ok: false, error: 'element is disabled or read-only' };
        if (tag === 'select') {
            var idx = -1;
            for (var i = 0; i < el.options.length; i++) {
                if (el.options[i].value === String(value) || el.options[i].text.trim() === String(value)) { idx = i; break; }
            }
            if (idx < 0) return { ok: false, error: 'no option ' + value };
            el.selectedIndex = idx;
            fire(el, ['input', 'change']);
            return { ok: true, value: el.value };
        }
        if (tag === 'input' && /^(checkbox|radio)$/i.test(el.type)) {
            var want = value === true || value === 'true' || value === 'on' || value === 1;
            if (el.checked !== want) el.click();
            return { ok: true, checked: el.checked };
        }
        if (el.isContentEditable && tag !== 'input' && tag !== 'textarea') {
            el.focus();
            el.textContent = String(value);
            fire(el, ['input']);
            return { ok: true };
        }
        var proto = tag === 'textarea' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        var setter = Object.getOwnPropertyDescriptor(proto, 'value');
        el.focus({ preventScroll: true });
        if (setter && setter.set) setter.set.call(el, String(value));
        else el.value = String(value);
        try {
            el.dispatchEvent(new InputEvent('input', { bubbles: true, composed: true, data: String(value), inputType: 'insertReplacementText' }));
        } catch (e) {
            fire(el, ['input']);
        }
        fire(el, ['change']);
        return { ok: true, value: el.type === 'password' ? '•••' : el.value };
    }

    function submit(id) {
        var el = resolve(id);
        if (!el) return { ok: false, error: 'unknown or detached element ' + id };
        var form = el.tagName === 'FORM' ? el : el.form || (el.closest && el.closest('form'));
        if (!form) return { ok: false, error: 'element is not in a form' };
        try {
            if (typeof form.requestSubmit === 'function') form.requestSubmit();
            else form.submit();
        } catch (e) {
            return { ok: false, error: String(e) };
        }
        return { ok: true, form: idFor(form) };
    }

    function scrollBy(dx, dy) {
        window.scrollBy({ left: dx || 0, top: dy || 0, behavior: 'instant' });
        return { ok: true, scrollX: Math.round(window.scrollX), scrollY: Math.round(window.scrollY) };
    }

    // A simple reader extraction for the UI's quick path; full Readability
    // runs in the Rust core on reader.html.
    function reader() {
        var candidates = Array.prototype.slice.call(document.querySelectorAll('article, main, [role=main], #content, .content, .post, .entry-content'));
        var best = null, bestLen = 0;
        candidates.forEach(function(c) {
            var len = textOf(c).length;
            if (len > bestLen) { best = c; bestLen = len; }
        });
        if (!best || bestLen < 500) {
            var blocks = document.querySelectorAll('div, section');
            for (var i = 0; i < blocks.length; i++) {
                var ps = blocks[i].querySelectorAll(':scope > p');
                var len = 0;
                for (var j = 0; j < ps.length; j++) len += textOf(ps[j]).length;
                if (len > bestLen) { best = blocks[i]; bestLen = len; }
            }
        }
        best = best || document.body;
        var meta = function(sel) { var m = document.querySelector(sel); return m ? m.getAttribute('content') || '' : ''; };
        return {
            url: location.href,
            title: meta('meta[property="og:title"]') || document.title,
            byline: meta('meta[name="author"]'),
            siteName: meta('meta[property="og:site_name"]'),
            excerpt: meta('meta[name="description"]') || meta('meta[property="og:description"]'),
            lang: document.documentElement.lang || '',
            html: best ? best.innerHTML.slice(0, 2000000) : '',
            text: best ? textOf(best).slice(0, 500000) : ''
        };
    }

    var api = {
        snapshot: snapshot, locate: locate, click: click, focus: focus, setValue: setValue,
        submit: submit, text: visibleText, html: html, reader: reader, scrollBy: scrollBy
    };
    Object.freeze(api);
    Object.defineProperty(window, '__pacificAgent', { value: api, writable: false, configurable: false });
})();
