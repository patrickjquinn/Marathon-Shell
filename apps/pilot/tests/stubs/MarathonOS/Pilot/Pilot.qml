pragma Singleton
import QtQml

// The runner's client of pilotd, for the tests: answers from properties,
// records what the app asked.
QtObject {
    property bool connected: true
    property bool offline: false
    property bool busy: false
    property string lastResponse: ""
    property string error: ""
    property bool voiceAvailable: false
    property string modelState: "{}"
    property var downloads: []
    property var settingsValue: ({
            consent: {},
            onboarded: true,
            guide: []
        })
    property var asked: []
    property int listens: 0
    property int refreshes: 0

    signal turnFinished(string json)
    signal wiped
    signal eventsRequested
    signal sheetRequested
    signal listenRequested
    signal nowChanged(string json)
    signal timerExtended(int oldCookie, string json)
    signal clockCancelled(int cookie)
    signal turnProgress(string json)

    function reset() {
        busy = false;
        voiceAvailable = false;
        modelState = "{}";
        downloads = [];
        asked = [];
        listens = 0;
        refreshes = 0;
        settingsValue = {
            consent: {},
            onboarded: true,
            guide: []
        };
    }
    function ask(text, spoken) {
        asked = asked.concat([text]);
        busy = true;
    }
    function finish(json) {
        busy = false;
        turnFinished(json);
    }
    function confirm(id, approved) {
    }
    function settings() {
        return JSON.stringify(settingsValue);
    }
    function setConsent(name, on) {
        return "";
    }
    function clearOnScreen() {
    }
    function openUrl(url) {
    }
    function clearConversation() {
    }
    function capabilities() {
        return "[]";
    }
    function memories() {
        return "[]";
    }
    function forget(id) {
        return true;
    }
    function setGuide(step, done) {
        return "";
    }
    function setName(name) {
        return "";
    }
    function egressLog(limit) {
        return "[]";
    }
    function exportTo(path) {
        return "";
    }
    function defaultExportPath() {
        return "/tmp/pilot-export.json";
    }
    function wipe() {
        return "";
    }
    function voiceModelsBytes() {
        return 0;
    }
    function removeVoiceModels() {
        return "";
    }
    function downloadModels(allowMetered) {
        downloads = downloads.concat([allowMetered]);
    }
    function triage() {
        return "[]";
    }
    function listen() {
        listens++;
    }
    function look(question, path) {
    }
    function photoPath() {
        return "/tmp/pilot-look.jpg";
    }
    function refreshNow() {
        refreshes++;
    }
    function cancelClock(cookie) {
    }
    function extendTimer(cookie, seconds) {
    }
}
