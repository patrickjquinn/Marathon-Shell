pragma Singleton
import QtQuick

QtObject {
    property var suggestions: []
    property string correction: ""
    property string suggestedFor: ""
    function suggest(typed, taps, before) {
        suggestedFor = typed;
        correction = typed;
    }
    function correctionFor(typed, taps, before) {
        return typed;
    }
    function swipe(points, before) {
        return [];
    }
    function nextWords(before) {
        return [];
    }
    function learn(before, word) {
    }
    function setKeys(keys, pitch) {
    }
    function setLanguage(language) {
    }
}
