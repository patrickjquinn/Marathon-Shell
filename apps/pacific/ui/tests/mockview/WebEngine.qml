// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Mock of the web view's WebEngine singleton.
pragma Singleton
import QtQuick

QtObject {
    enum CacheModel { DocumentViewer, WebBrowser, DocumentBrowser }
    readonly property string version: "mock"
    readonly property WebProfile defaultProfile: WebProfile {}
    readonly property WebProfile privateProfile: WebProfile { ephemeral: true }
    property int cacheModel: WebEngine.WebBrowser
    property var preferredLanguages: []
    property bool spellChecking: true
    property var spellCheckingLanguages: ["en_GB"]
    readonly property var availableSpellCheckingLanguages: ["de_DE", "en_GB", "en_US", "es_ES", "fi_FI", "fr_FR", "ga_IE", "it_IT", "nl_NL", "pl_PL", "pt_BR", "pt_PT", "sv_SE"]
    property int memoryLimitMB: 0
    property real conservativeThreshold: 0.33
    property real strictThreshold: 0.5
    property real killThreshold: 0
    property real memoryPollInterval: 30
    readonly property string gpuMode: "mock"
}
