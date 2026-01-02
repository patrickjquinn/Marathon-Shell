pragma Singleton
import MarathonOS.Shell
import QtQuick

Item {
    id: dictionary

    property var cachedPredictions: []
    property string lastPredictionPrefix: ""

    function predict(prefix) {
        if (!prefix || prefix.length === 0)
            return [];

        if (typeof WordEngine === 'undefined' || WordEngine === null || !WordEngine.enabled)
            return [];

        if (dictionary.lastPredictionPrefix !== prefix) {
            dictionary.lastPredictionPrefix = prefix;
            dictionary.cachedPredictions = [];
            WordEngine.requestPredictions(prefix, 3);
        }
        return cachedPredictions;
    }

    function learnWord(word) {
        if (!word || word.length < 2)
            return;

        if (typeof WordEngine !== 'undefined' && WordEngine !== null && WordEngine.enabled)
            WordEngine.learnWord(word);
    }

    function hasWord(word) {
        if (!word)
            return false;

        if (typeof WordEngine !== 'undefined' && WordEngine !== null && WordEngine.enabled)
            return WordEngine.hasWord(word);

        return false;
    }

    Connections {
        function onPredictionsReady(prefix, predictions) {
            if (prefix === dictionary.lastPredictionPrefix)
                dictionary.cachedPredictions = predictions;
        }

        target: typeof WordEngine !== 'undefined' ? WordEngine : null
    }
}
