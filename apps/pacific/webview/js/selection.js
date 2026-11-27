// SPDX-FileCopyrightText: 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-browser apps/wpe/WPEUserScripts.h)
// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MPL-2.0
//
// Text selection and long-press bridge, from Atlantic's kSelectionBridge
// (atlantic-browser c150119). Runs in Pacific's isolated script world, so the
// page can neither see nor break it. Reports:
//   pacificSelection  {type:'select', text, startX/Y, endX/Y} or {type:'clear'}
//                     (CSS px, viewport coordinates) for the selection handles
//   pacificContext    {imageUrl, linkUrl, selectionText, editable, pageUrl, x, y}
//                     on a long press, for the context menu; in a text field
//                     {editable, editMenu, secret, hasText, selected, pageUrl, x, y}
// Changes from Atlantic: handler names, and the world guard.
(function() {
    if (window.__pacificSelectionInstalled) return;
    window.__pacificSelectionInstalled = true;

    function caretRect(node, offset) {
        if (!node)
            return null;
        var range = document.createRange();
        try {
            range.setStart(node, offset);
            range.setEnd(node, offset);
        } catch (e) {
            return null;
        }
        var rect = range.getBoundingClientRect();
        if (!rect)
            return null;
        return rect;
    }

    function pointRange(x, y) {
        if (document.caretRangeFromPoint)
            return document.caretRangeFromPoint(x, y);
        if (document.caretPositionFromPoint) {
            var p = document.caretPositionFromPoint(x, y);
            if (p) {
                var r = document.createRange();
                r.setStart(p.offsetNode, p.offset);
                r.collapse(true);
                return r;
            }
        }
        return null;
    }

    function selectWordAtPoint(x, y) {
        var sel = window.getSelection ? window.getSelection() : null;
        if (!sel)
            return false;

        var range = pointRange(x, y);
        if (!range)
            return false;

        var node = range.startContainer;
        var offset = range.startOffset;
        if (!node)
            return false;

        if (node.nodeType !== Node.TEXT_NODE) {
            if (node.childNodes && node.childNodes.length) {
                if (offset >= node.childNodes.length)
                    offset = node.childNodes.length - 1;
                if (offset < 0)
                    offset = 0;
                var child = node.childNodes[offset];
                if (child && child.nodeType === Node.TEXT_NODE) {
                    node = child;
                    offset = 0;
                }
            }
        }

        if (node.nodeType !== Node.TEXT_NODE)
            return false;

        var text = node.data || '';
        if (!text.length)
            return false;

        var start = offset;
        var end = offset;
        while (start > 0 && /\S/.test(text.charAt(start - 1)))
            start--;
        while (end < text.length && /\S/.test(text.charAt(end)))
            end++;

        if (start === end) {
            if (end < text.length)
                end++;
            else if (start > 0)
                start--;
        }

        try {
            var wordRange = document.createRange();
            wordRange.setStart(node, start);
            wordRange.setEnd(node, end);
            sel.removeAllRanges();
            sel.addRange(wordRange);
            return true;
        } catch (e) {
            return false;
        }
    }

    // The focused text field's selection, which the document's does not
    // show; a password's never leaves the page.
    function fieldSelection() {
        var el = document.activeElement;
        if (!el || !textControl(el) || el.selectionStart === el.selectionEnd)
            return null;
        if ((el.type || '').toLowerCase() === 'password')
            return { type: 'clear' };
        var rect = el.getBoundingClientRect();
        return {
            type: 'select',
            text: el.value.substring(el.selectionStart, el.selectionEnd),
            startX: rect.left,
            startY: rect.bottom,
            endX: rect.right,
            endY: rect.bottom
        };
    }

    function selectionPayload() {
        var field = fieldSelection();
        if (field)
            return field;
        var sel = window.getSelection ? window.getSelection() : null;
        if (!sel || !sel.rangeCount || sel.isCollapsed)
            return { type: 'clear' };

        var text = sel.toString();
        if (!text)
            return { type: 'clear' };

        var range = sel.getRangeAt(0);
        // Use range.start/end (order-invariant) instead of anchor/focus (drag-direction dependent).
        // Avoid getClientRects() — it forces synchronous layout on every selectionchange, which
        // is very expensive on heavy-DOM pages. Caret rects on collapsed ranges are much cheaper.
        var startRect = caretRect(range.startContainer, range.startOffset);
        var endRect = caretRect(range.endContainer, range.endOffset);
        var bounds = (!startRect || !endRect) ? range.getBoundingClientRect() : null;

        var sx = startRect ? startRect.left : (bounds ? bounds.left : 0);
        var sy = startRect ? startRect.bottom : (bounds ? bounds.bottom : 0);
        var ex = endRect ? endRect.right : (bounds ? bounds.right : 0);
        var ey = endRect ? endRect.bottom : (bounds ? bounds.bottom : 0);

        return {
            type: 'select',
            text: text,
            startX: sx,
            startY: sy,
            endX: ex,
            endY: ey,
            cursorX: ex,
            cursorY: ey,
            sx: sx,
            sy: sy,
            ex: ex,
            ey: ey
        };
    }

    var pendingSelectionRaf = null;

    function flushSelection() {
        try {
            window.webkit.messageHandlers.pacificSelection.postMessage(selectionPayload());
        } catch (ex) {
            console.error('[pacific-selection] postMessage error: ' + ex);
        }
    }

    // Throttle continuous selectionchange events to one IPC message per animation frame.
    function postSelection() {
        if (pendingSelectionRaf) return;
        pendingSelectionRaf = requestAnimationFrame(function() {
            pendingSelectionRaf = null;
            flushSelection();
        });
    }

    // For gesture-end events, cancel any pending frame and send immediately so the
    // final handle positions are never one frame late.
    function postSelectionFinal() {
        if (pendingSelectionRaf) {
            cancelAnimationFrame(pendingSelectionRaf);
            pendingSelectionRaf = null;
        }
        flushSelection();
    }

    var longPressTimer = null;
    var longPressPoint = null;
    var longPressStartPoint = null;
    var longPressMoveThreshold = 12;
    // Set when the JS touch-timer path opened the panel. That fires while the
    // finger is still down, so unlike the contextmenu path it cannot
    // preventDefault() the activation -- the click that arrives after touchend
    // has to be swallowed instead, or a long press on a link would navigate to
    // it as well as offering "Open in new tab".
    var longPressFired = false;

    function cancelLongPress() {
        if (longPressTimer) {
            clearTimeout(longPressTimer);
            longPressTimer = null;
        }
        longPressPoint = null;
        longPressStartPoint = null;
    }

    function imageUrlAtPoint(x, y) {
        var el = document.elementFromPoint(x, y);
        while (el) {
            if (el.tagName && el.tagName.toLowerCase() === 'img') {
                var src = el.currentSrc || el.src || el.getAttribute('src');
                if (src) return src;
            }
            el = el.parentElement;
        }
        return null;
    }

    function linkUrlAtPoint(x, y) {
        var el = document.elementFromPoint(x, y);
        while (el) {
            if (el.tagName && el.tagName.toLowerCase() === 'a' && el.href)
                return el.href;
            el = el.parentElement;
        }
        return null;
    }

    // Only http(s) links are worth a panel: mailto:/tel:/javascript: hrefs have
    // nothing sensible to open in a tab, and offering nothing is better than
    // swallowing the press. contextInfo.linkUrl still carries the raw href for
    // extensions -- this only gates the built-in action. Keep in sync with
    // ImageActionPanel.pendingLinkUrl.
    function isNavigableLink(url) {
        return !!url && /^https?:\/\//i.test(url);
    }

    function textControl(el) {
        var tag = el.tagName ? el.tagName.toLowerCase() : '';
        return tag === 'textarea' || (tag === 'input' && !/^(button|submit|reset|checkbox|radio|file|image|color|range|hidden)$/i
                .test(el.type || 'text'));
    }

    function editableElementAt(x, y) {
        var el = document.elementFromPoint(x, y);
        while (el) {
            if (el.isContentEditable || textControl(el))
                return el;
            el = el.parentElement;
        }
        return null;
    }

    function editableAtPoint(x, y) {
        return editableElementAt(x, y) !== null;
    }

    // A long press in a text field focuses it and asks for the edit bar.
    // Editable text selects the word held; an input's is left to Select all,
    // as a page cannot find the character under a point in one.
    function editableLongPress(x, y) {
        var el = editableElementAt(x, y);
        if (!el || linkUrlAtPoint(x, y))
            return false;
        if (document.activeElement !== el)
            el.focus();
        var control = textControl(el);
        if (!control)
            selectWordAtPoint(x, y);
        var selected = control ? el.selectionStart !== el.selectionEnd
                               : !!window.getSelection() && !window.getSelection().isCollapsed;
        try {
            window.webkit.messageHandlers.pacificContext.postMessage({
                editable: true,
                editMenu: true,
                secret: control && (el.type || '').toLowerCase() === 'password',
                hasText: control ? el.value.length > 0 : (el.textContent || '').length > 0,
                selected: selected,
                pageUrl: location.href,
                x: x, y: y
            });
        } catch(e) {}
        postSelectionFinal();
        return true;
    }

    // Reports what was long-pressed. The image URL keeps its own field because
    // the image panel has always been driven off it; the rest is what
    // browser.contextMenus needs to decide which items apply. Returns true when
    // there is anything worth showing a panel for -- a link counts, so a long
    // press on one opens the action panel instead of falling through to
    // word selection (and preventDefault() below stops the link activating).
    function postImageLongPress(x, y) {
        var imgUrl = imageUrlAtPoint(x, y);
        var linkUrl = linkUrlAtPoint(x, y);
        var editable = editableAtPoint(x, y);
        var selection = '';
        try {
            var sel = window.getSelection();
            if (sel && !sel.isCollapsed)
                selection = String(sel).substring(0, 1000);
        } catch(e) {}

        try {
            window.webkit.messageHandlers.pacificContext.postMessage({
                imageUrl: imgUrl || '',
                linkUrl: linkUrl || '',
                selectionText: selection,
                editable: editable,
                pageUrl: location.href,
                x: x, y: y
            });
        } catch(e) {}
        return !!imgUrl || isNavigableLink(linkUrl);
    }

    function beginLongPress(x, y) {
        cancelLongPress();
        // Cleared here rather than in cancelLongPress(): touchend cancels the
        // timer, and the click we mean to swallow only arrives after that. The
        // next gesture's touchstart is what retires a flag nothing consumed.
        longPressFired = false;
        longPressPoint = { x: x, y: y };
        longPressStartPoint = { x: x, y: y };
        longPressTimer = setTimeout(function() {
            longPressTimer = null;
            if (!longPressPoint) return;
            var lx = longPressPoint.x, ly = longPressPoint.y;
            longPressPoint = null;
            if (editableLongPress(lx, ly)) {
                longPressFired = true;
                return;
            }
            if (postImageLongPress(lx, ly)) {
                longPressFired = true;
                return;
            }
            if (selectWordAtPoint(lx, ly))
                postSelectionFinal();
        }, 350);
    }

    function touchPointFromEvent(e) {
        if (e.touches && e.touches.length)
            return e.touches[0];
        if (e.changedTouches && e.changedTouches.length)
            return e.changedTouches[0];
        return null;
    }

    document.addEventListener('selectionchange', postSelection, true);
    document.addEventListener('mouseup', postSelectionFinal, true);
    document.addEventListener('touchend', postSelectionFinal, {capture: true, passive: true});
    document.addEventListener('keyup', postSelectionFinal, true);
    document.addEventListener('select', postSelectionFinal, true);
    document.addEventListener('contextmenu', function(e) {
        // WebKit's native long-press fires contextmenu reliably (this is the
        // working text-selection trigger); the JS touch-timer above can be
        // pre-empted by the compositor's scroll/gesture handling. Check for an
        // image here too so the image panel uses the same dependable signal.
        cancelLongPress();
        // A field's spelling suggestions are WebKit's own menu: let it come.
        if (editableLongPress(e.clientX, e.clientY))
            return;
        if (postImageLongPress(e.clientX, e.clientY)) {
            e.preventDefault();
            return;
        }
        if (selectWordAtPoint(e.clientX, e.clientY)) {
            e.preventDefault();
            postSelectionFinal();
        }
    }, true);
    // A finger landing on a page that is still scrolling (a fling) catches
    // it: that touch never long-presses, as on iOS and Android, or holding a
    // caught page selected the word under the finger. Scroll events stop
    // within a frame of the page stopping; 120 ms covers a busy main thread.
    var lastScroll = { at: -1e9, target: null };
    document.addEventListener('scroll', function(e) {
        lastScroll.at = performance.now();
        lastScroll.target = e.target;
    }, {capture: true, passive: true});

    function scrollingUnder(target) {
        if (performance.now() - lastScroll.at > 120)
            return false;
        var scroller = lastScroll.target;
        if (!scroller || scroller === document || scroller === document.scrollingElement)
            return true;
        return scroller.contains && scroller.contains(target);
    }

    // passive:true lets WebKit compositor scroll without waiting for main-thread
    // confirmation that preventDefault() won't be called (none of these handlers call it)
    document.addEventListener('touchstart', function(e) {
        var p = touchPointFromEvent(e);
        if (!p)
            return;
        if (scrollingUnder(e.target)) {
            cancelLongPress();
            longPressFired = false;
            return;
        }
        beginLongPress(p.clientX, p.clientY);
    }, {capture: true, passive: true});
    document.addEventListener('touchmove', function(e) {
        var p = touchPointFromEvent(e);
        if (!p || !longPressStartPoint)
            return;
        var dx = p.clientX - longPressStartPoint.x;
        var dy = p.clientY - longPressStartPoint.y;
        if ((dx * dx) + (dy * dy) > longPressMoveThreshold * longPressMoveThreshold)
            cancelLongPress();
    }, {capture: true, passive: true});
    document.addEventListener('click', function(e) {
        if (!longPressFired)
            return;
        longPressFired = false;
        e.preventDefault();
        e.stopPropagation();
    }, true);
    document.addEventListener('touchcancel', cancelLongPress, {capture: true, passive: true});
    document.addEventListener('touchend', cancelLongPress, {capture: true, passive: true});
})();
