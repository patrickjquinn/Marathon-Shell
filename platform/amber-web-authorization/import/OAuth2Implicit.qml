// SPDX-FileCopyrightText: 2021 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/****************************************************************************
**
** BSD 3-Clause License.  See LICENSE for full text.
** Copyright (c) 2021 Open Mobile Platform LLC.
** All rights reserved.
**
****************************************************************************/

import QtQml 2.0
import Amber.Web.Authorization 1.0
import "httpcontent.js" as OAuthHttpContent

QtObject {
    id: root

    property alias timeout: listener.timeout

    property alias userAgent: oauth2.userAgent
    property alias redirectUri: oauth2.redirectUri

    property alias authorizationEndpoint: oauth2.authorizationEndpoint
    property alias tokenEndpoint: oauth2.tokenEndpoint
    property alias refreshEndpoint: oauth2.refreshEndpoint

    property alias clientId: oauth2.clientId
    property alias clientSecret: oauth2.clientSecret // shouldn't be required, but some services do...
    // Modified by Shipwright for Qt 6: Qt 6 does not pass undefined as an
    // empty QStringList to generateScope(); unset scopes mean no scopes.
    property var scopes: []
    property string scopesSeparator: ' '
    property alias state: oauth2.state

    property alias customParameters: oauth2.customParameters

    // this signal is emitted after receiving the token
    signal receivedAccessToken(var token)

    // this signal is emitted on error
    signal errorOccurred(var error)

    function authorizationUrl() {
        if (redirectUri.length === 0
                || redirectUri == listener.uri) {
            listener.startListening()
        }
        return oauth2.generateAuthorizationUrl()
    }

    function authorizeInBrowser() {
        Qt.openUrlExternally(authorizationUrl())
    }

    function refreshAccessToken(refreshToken) {
        oauth2.refreshAccessToken(refreshToken)
    }

    property OAuth2 oauth: OAuth2 {
        id: oauth2
        flowType: OAuth2.ImplicitFlow
        scope: generateScope(root.scopes, root.scopesSeparator)
        state: generateState()
        onErrorChanged: { listener.stopListening(); root.errorOccurred(error) }
        onReceivedAccessToken: { listener.stopListening(); root.receivedAccessToken(token) }
    }

    property RedirectListener redirectListener: RedirectListener {
        id: listener
        timeout: 60 * 5
        httpContent: OAuthHttpContent.data
        onFailed: root.errorOccurred({ "code": Error.NetworkError,
                                       "message": "Unable to listen for redirect",
                                       "httpCode": 0 })
        onTimedOut: root.errorOccurred({ "code": Error.TimedOutError,
                                       "message": "Timed out waiting for redirect",
                                       "httpCode": 0 })
        onReceivedRedirect: {
            var data = oauth2.parseRedirectUri(redirectUri)
            if (data.access_token && data.access_token.length) {
                root.receivedAccessToken(data)
            } else {
                stopListening()
                root.errorOccurred({ "code": Error.ParseError,
                                     "message": "Unable to parse access token from redirect: " + redirectUri,
                                     "httpCode": 0 })
            }
        }
    }
}
