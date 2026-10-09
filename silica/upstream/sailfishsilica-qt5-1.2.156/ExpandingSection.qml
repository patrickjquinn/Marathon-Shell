/****************************************************************************************
**
** Copyright (C) 2015 Jolla Ltd.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/

import QtQuick 2.0
import Sailfish.Silica 1.0
import "private"
import "private/Util.js" as Util

/*
If this is made into public API, consider having 'content' as a variant that can be url/component/item
like Page::acceptDestination, ListItem::menu, etc.
*/

Item {
    id: root

    property alias title: titleLabel.text
    property alias content: loader

    property bool expanded
    property real buttonHeight: Theme.itemSizeMedium

    // don't use default of horizontalPageMargin, as arrow icons should be closer to the edge of the screen
    property real leftMargin: _group ? _group.leftMargin : Theme.paddingMedium
    property real rightMargin: _group ? _group.leftMargin : Theme.paddingMedium

    property Item _group
    readonly property int _animationDuration: _group ? _group.animationDuration : 200
    property int __silica_expandingsection

    width: parent ? parent.width : 0
    height: contentContainer.height + button.contentHeight

    onParentChanged: {
        _group = Util.findParentWithProperty(root, "__silica_expandingsectiongroup")
    }

    onExpandedChanged: {
        expandBehavior.enabled = _group && _group._initialized
        if (expanded) {
            loader.active = true
        }
    }

    // Dynamically animating the Loader height doesn't work consistently depending on how the
    // child content's height and implicitHeight is set, so resize this wrapper Item instead.
    Item {
        id: contentContainer

        anchors.top: button.bottom
        width: parent.width
        height: loader.item && root.expanded ? loader.height : 0
        clip: loader.item && expandAnim.running
        opacity: loader.item && root.expanded ? 1 : 0

        // Don't use Easing.InOutQuad in height behavior; that causes the flickable contentY change
        // to also animate with InOutQuad easing and jump slightly, which looks like a bug.
        Behavior on height {
            id: expandBehavior
            enabled: false
            NumberAnimation {
                id: expandAnim
                duration: root._animationDuration
                onRunningChanged: {
                    // disable the behaviour for height animations outside of expansion changes
                    if (!running) {
                        expandBehavior.enabled = false
                    }
                }
            }
        }
        Behavior on opacity { FadeAnimation { duration: root._animationDuration } }

        Loader {
            id: loader
            width: parent.width
            active: false
            onStatusChanged: {
                if (status == Loader.Error) {
                    console.log("ExpandingSection: unable to loader source content")
                }
            }
        }
    }

    BackgroundItem {
        id: button

        width: parent.width
        height: contentHeight
        contentHeight: root.buttonHeight
        visible: contentHeight > 0

        onClicked: {
            if (_group) {
                var sectionIndex = _group.indexOfSection(root)
                _group.currentIndex = (_group.currentIndex == sectionIndex ? -1 : sectionIndex)
            } else {
                expanded = !expanded
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Theme.rgba(button.palette.highlightBackgroundColor, 0.1)
                }
                GradientStop {
                    position: 1.0
                    color: "transparent"
                }
            }
        }

        Icon {
            id: iconLeftImg

            anchors {
                right: titleLabel.left
                rightMargin: Theme.paddingSmall
                verticalCenter: parent.verticalCenter
            }

            source: "image://theme/icon-m-right"
            highlighted: button.down
            opacity: root.expanded ? 1.0 : 0.0
            Behavior on opacity { FadeAnimation { duration: root._animationDuration } }
        }

        Label {
            id: titleLabel

            width: Math.min(
                        implicitWidth,
                        parent.width - (root.expanded ? anchors.leftMargin : anchors.rightMargin))
            anchors {
                left: undefined
                leftMargin: root.leftMargin + iconLeftImg.width + Theme.paddingSmall
                right: parent.right
                rightMargin: root.rightMargin + iconRightImg.width + Theme.paddingSmall
                verticalCenter: parent.verticalCenter
            }

            color: {
                if (button.highlighted) {
                    return palette.secondaryHighlightColor
                } else if (root.expanded) {
                    return palette.highlightColor
                } else {
                    return palette.primaryColor
                }
            }
            font.pixelSize: Theme.fontSizeLarge
            truncationMode: TruncationMode.Fade

            states: [
                State {
                    name: "expanded"
                    when: root.expanded

                    AnchorChanges {
                        target: titleLabel
                        anchors.right: undefined
                        anchors.left: parent.left
                    }
                }
            ]

            transitions: [
                Transition {
                    // Prevent expansion from animating when the group expands its initial
                    // current section.
                    enabled: expandBehavior.enabled

                    AnchorAnimation { duration: root._animationDuration }
                }
            ]
        }

        Icon {
            id: iconRightImg

            anchors {
                right: parent.right
                rightMargin: root.rightMargin
                verticalCenter: parent.verticalCenter
            }

            source: "image://theme/icon-m-down"
            highlighted: button.down
            opacity: root.expanded ? 0.0 : 1.0
            Behavior on opacity { FadeAnimation { duration: root._animationDuration } }
        }
    }
}
