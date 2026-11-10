// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: MPL-2.0
/****************************************************************************
**
** Copyright (c) 2021 Open Mobile Platform LLC.
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

import QtQuick 2.6
import Sailfish.Share 1.0

ShareAction {
    id: shareAction

    function shareLink(linkHref, linkTitle, title) {
        _share(
            //: Header for link sharing
            //% "Share link"
            title ? title : qsTrId("sailfish_browser-he-share_link"),
            {
                "type": "text/x-url",
                "linkTitle": linkTitle,
                "status": linkHref,
            })
    }

    function shareText(text) {
        _share(
            //: Header for text sharing
            //% "Share"
            qsTrId("sailfish_browser-he-share"),
            {
                "name": text,
                "data": text,
                "type": "text/plain",
                "status": text,
            })
    }

    function _share(title, content) {
        shareAction.title = title
        shareAction.resources = [content]
        shareAction.mimeType = content.type
        shareAction.trigger()
    }
}
