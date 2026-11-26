// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica

// Theme.pagedScrolling (here from KEEL_THEME_PAGED_SCROLLING): a list too long
// for its view does not follow the finger, and a swipe moves it a page, its
// height less a row, in one jump.
TestCase {
    id: tc

    name: "PagedScrolling"
    when: windowShown

    // Its own window: the test case's is not shown with a size here.
    Window {
        width: 300
        height: 800
        visible: true

        SilicaListView {
            id: list

            width: 300
            height: 400
            model: 60
            delegate: Item {
                width: 300
                height: 50
            }
        }

        // Beside the long list, not over it.
        SilicaListView {
            id: short

            y: 400
            width: 300
            height: 400
            model: 2
            delegate: Item {
                width: 300
                height: 50
            }
        }
    }

    SignalSpy {
        id: moves

        target: list
        signalName: "contentYChanged"
    }

    function swipe(dy) {
        const touch = touchEvent(list);
        touch.press(0, list, 150, 300).commit();
        for (let i = 1; i <= 10; ++i) {
            wait(30);
            touch.move(0, list, 150, 300 + dy * i / 10).commit();
        }
        touch.release(0, list, 150, 300 + dy).commit();
    }

    function init() {
        list.contentY = list.originY;
        moves.clear();
    }

    function test_onlyWhatOverflowsPages() {
        verify(Theme.pagedScrolling);
        verify(!list.interactive);
        verify(short.interactive);
    }

    function test_aShortSwipeMovesNothing() {
        swipe(-30);
        compare(moves.count, 0);
    }

    function test_aSwipeMovesAPageInOneJump() {
        const y0 = list.contentY;
        swipe(-150);
        compare(moves.count, 1);
        compare(list.contentY, y0 + list.height - Theme.itemSizeSmall);
        swipe(150);
        compare(list.contentY, y0);
    }
}
