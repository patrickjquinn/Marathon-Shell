pragma Singleton
import QtQuick

QtObject {
    property var cachedPredictions: []
    property string lastPredictionPrefix: ""
    function predict(prefix) {
        return [];
    }
    function correct(word) {
        return word;
    }
    function getPhraseCompletions(context) {
        return [];
    }
    function learnWord(word) {
    }
}
