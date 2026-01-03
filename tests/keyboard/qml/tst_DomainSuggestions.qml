import QtQuick
import QtTest

TestCase {
    property string currentWord: ""
    property var currentPredictions: []
    property string inputMode: "text"
    property bool shouldShowPredictions: true
    property var predictCalls: []

    function init() {
        currentWord = "";
        currentPredictions = [];
        inputMode = "text";
        shouldShowPredictions = true;
        predictCalls = [];
    }

    function updatePredictions() {
        if (currentWord.length === 0) {
            currentPredictions = [];
            return;
        }
        var isEmail = inputMode === "email";
        var isUrl = inputMode === "url";
        if (isEmail || isUrl) {
            if (mockDomainSuggestions.shouldShowDomainSuggestions(currentWord, isEmail, isUrl)) {
                var domainSugs = mockDomainSuggestions.getSuggestions(currentWord, isEmail);
                if (domainSugs.length > 0) {
                    currentPredictions = domainSugs;
                    return;
                }
            }
        }
        if (shouldShowPredictions) {
            mockDictionary.predict(currentWord);
            currentPredictions = mockDictionary.cachedPredictions;
        } else {
            currentPredictions = [];
        }
    }

    function test_updatePredictions_emptyWord() {
        init();
        currentWord = "";
        updatePredictions();
        compare(currentPredictions.length, 0);
    }

    function test_updatePredictions_callsDictionaryPredict() {
        init();
        currentWord = "hello";
        updatePredictions();
        compare(predictCalls.length, 1);
        compare(predictCalls[0], "hello");
    }

    function test_updatePredictions_emailMode_domainSuggestions() {
        init();
        inputMode = "email";
        currentWord = "user@";
        updatePredictions();
        verify(currentPredictions.length > 0);
        verify(currentPredictions.indexOf("gmail.com") !== -1);
    }

    function test_updatePredictions_textMode_noDomains() {
        init();
        inputMode = "text";
        currentWord = "user@";
        updatePredictions();
        compare(predictCalls.length, 1);
    }

    function test_updatePredictions_predictionsDisabled() {
        init();
        shouldShowPredictions = false;
        currentWord = "test";
        updatePredictions();
        compare(currentPredictions.length, 0);
    }

    function test_updatePredictions_normalWord() {
        init();
        currentWord = "test";
        updatePredictions();
        verify(currentPredictions.length > 0);
    }

    function test_updatePredictions_urlMode_dotSuggestions() {
        init();
        inputMode = "url";
        currentWord = "example.";
        updatePredictions();
        verify(currentPredictions.length > 0);
        verify(currentPredictions.indexOf(".com") !== -1);
    }

    function test_updatePredictions_emailMultipleDomains() {
        init();
        inputMode = "email";
        currentWord = "test@";
        updatePredictions();
        verify(currentPredictions.length >= 4);
    }

    name: "DomainSuggestionTests"

    QtObject {
        id: mockDictionary

        property var cachedPredictions: ["test1", "test2", "test3"]

        function predict(word) {
            predictCalls.push(word);
        }
    }

    QtObject {
        id: mockDomainSuggestions

        function shouldShowDomainSuggestions(word, isEmail, isUrl) {
            return word.indexOf("@") !== -1 || word.indexOf(".") !== -1;
        }

        function getSuggestions(word, isEmail) {
            if (isEmail && word.indexOf("@") !== -1)
                return ["gmail.com", "yahoo.com", "outlook.com", "icloud.com"];

            if (word.indexOf(".") !== -1)
                return [".com", ".org", ".net", ".io"];

            return [];
        }
    }
}
