/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
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

Page {
    id: dialog

    /* Items from the Harmattan Dialog component interface, not supported:
    property Item content
    property Item buttons
    property Item style
    property Item title
    property Item visualParent
    property int status
    */

    // XXX deprecated
    // the custom dialog component to be created
    property Component sourceComponent
    onSourceComponentChanged: console.log("Dialog::sourceComponent is deprecated. Dialog content can now be declared directly within the dialog container itself.")

    // XXX deprecated
    // once open() has been called, this is the created instance
    // of the custom dialog component
    property Item item

    // a DialogResult enum value
    property int result

    // the page or component that should be pushed on the page stack if the dialog is accepted
    property alias acceptDestination: dialog._forwardDestination
    property alias acceptDestinationProperties: dialog._forwardDestinationProperties
    property alias acceptDestinationAction: dialog._forwardDestinationAction
    property alias acceptDestinationInstance: dialog._forwardDestinationInstance
    property var acceptDestinationReplaceTarget

    property alias canAccept: dialog.canNavigateForward

    property bool acceptPending: (dialog._navigationPending === PageNavigation.Forward)

    property bool _activated
    property int __silica_dialog
    property Item _dialogHeader

    signal accepted
    signal rejected
    signal acceptBlocked

    // Private signals, although we can't prefix with _
    // Custom dialogs can create handlers for these to be notified
    // when the dialog is opened and closed.
    signal opened
    signal done

    // Public functions
    function open(replace, operationType) {
        if (replace) {
            pageStack.animatorReplace(dialog, undefined, operationType)
        } else {
            pageStack.animatorPush(dialog, undefined, operationType)
        }
    }

    function accept() {
        pageStack.navigateForward()
    }

    function reject() {
        pageStack.navigateBack()
    }

    function close() {
        if (sourceComponent !== null && item == null) {
            return
        }
        done()
        pageStack.pop()
    }

    function _dialogDone(dialogResult) {
        if (dialogResult !== result) {
            result = dialogResult
            done()

            if (result == DialogResult.Accepted) {
                accepted()
            } else if (result == DialogResult.Rejected) {
                rejected()
            }
        }
    }

    forwardNavigation: true

    onAcceptDestinationReplaceTargetChanged: {
        // can't alias acceptDestinationReplaceTarget to _forwardDestinationReplaceTarget due to QTBUG-33286
        if (acceptDestinationReplaceTarget === undefined) {
            _forwardDestinationReplaceTarget = undefined
        } else if (acceptDestinationReplaceTarget === null) {
            _forwardDestinationReplaceTarget = null
        } else {
            _forwardDestinationReplaceTarget = acceptDestinationReplaceTarget
        }
    }

    onPageContainerChanged: {
        if (pageContainer) {
            // We have been added to a container
            if (sourceComponent !== null && item == null) {
                console.log('WARNING: Dialog::sourceComponent is deprecated.')
                item = sourceComponent.createObject(dialog)
            }
        } else {
            // Emit done if we haven't previously
            if (result == DialogResult.None && _navigation == PageNavigation.NoNavigation) {
                done()
            }

            // If we are reactivated, we will have been opened again
            _activated = false
        }
    }

    onStatusChanged: {
        if (status == PageStatus.Activating) {
            // Any time the dialog is activated, reset the result
            result = DialogResult.None
            if (!_activated) {
                _activated = true
                // But only open the dialog once
                opened()
            }
        }
    }

    on_NavigationChanged: {
        if (_navigation == PageNavigation.Forward) {
            // Treat as acceptance
            _dialogDone(DialogResult.Accepted)
        } else if (_navigation == PageNavigation.Back) {
            // Treat as rejection
            _dialogDone(DialogResult.Rejected)
        }
    }
}
