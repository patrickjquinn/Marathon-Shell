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

    property alias userAgent: oauth1.userAgent
    property alias redirectUri: oauth1.redirectUri // oauth_callback

    property alias requestTokenEndpoint: oauth1.requestTokenEndpoint
    property alias authorizeTokenEndpoint: oauth1.authorizeTokenEndpoint
    property alias accessTokenEndpoint: oauth1.accessTokenEndpoint

    property alias consumerKey: oauth1.consumerKey
    property alias consumerSecret: oauth1.consumerSecret

    property alias customParameters: oauth1.customParameters

    signal receivedTemporaryToken(string oauthToken, string oauthTokenSecret)
    signal receivedTokenAuthorization(string oauthToken, string oauthVerifier)
    signal receivedAccessToken(string oauthToken, string oauthTokenSecret)
    signal errorOccurred(var error)

    function requestTemporaryToken() {
        oauth1.requestTemporaryToken()
    }

    function authorizationUrl(oauthToken) {
        if (redirectUri.length === 0
                || redirectUri == listener.uri) {
            listener.startListening()
        }
        return oauth1.generateAuthorizationUrl(oauthToken)
    }

    function authorizeInBrowser(oauthToken, oauthTokenSecret) {
        oauth1.temporaryToken = oauthToken
        oauth1.temporaryTokenSecret = oauthTokenSecret
        Qt.openUrlExternally(authorizationUrl(oauthToken))
    }

    property OAuth1 oauth: OAuth1 {
        id: oauth1
        property var temporaryToken
        property var temporaryTokenSecret
        flowType: OAuth2.AuthorizationCodeFlow
        redirectUri: listener.uri
        onErrorChanged: { listener.stopListening(); root.errorOccurred(error) }
        onReceivedTemporaryToken: { root.receivedTemporaryToken(oauthToken, oauthTokenSecret) }
        onReceivedAccessToken: { listener.stopListening(); root.receivedAccessToken(oauthToken, oauthTokenSecret) }
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
            var data = oauth1.parseRedirectUri(redirectUri)
            if (data.oauth_verifier && data.oauth_verifier.length) {
                // give the client a chance to update customParameters etc
                root.receivedTokenAuthorization(data.oauth_token, data.oauth_verifier)
                oauth1.requestAccessToken(oauth1.temporaryToken, oauth1.temporaryTokenSecret, data.oauth_verifier)
            } else {
                stopListening()
                root.errorOccurred({ "code": Error.ParseError,
                                     "message": "Unable to parse oauth_verifier from redirect: " + redirectUri,
                                     "httpCode": 0 })
            }
        }
    }
}
