pragma Singleton
import QtQuick

QtObject {
    id: autoCorrect

    property var commonTypos: ({
            "teh": "the",
            "adn": "and",
            "youre": "you're",
            "dont": "don't",
            "cant": "can't",
            "wont": "won't",
            "didnt": "didn't",
            "doesnt": "doesn't",
            "hasnt": "hasn't",
            "havent": "haven't",
            "isnt": "isn't",
            "wasnt": "wasn't",
            "werent": "weren't",
            "shouldnt": "shouldn't",
            "wouldnt": "wouldn't",
            "couldnt": "couldn't",
            "thats": "that's",
            "whats": "what's",
            "hes": "he's",
            "shes": "she's",
            "its": "it's",
            "im": "I'm",
            "youve": "you've",
            "theyve": "they've",
            "weve": "we've",
            "ive": "I've",
            "recieve": "receive",
            "beleive": "believe",
            "neccessary": "necessary",
            "seperate": "separate",
            "definately": "definitely",
            "occured": "occurred",
            "begining": "beginning",
            "tommorrow": "tomorrow",
            "untill": "until",
            "alot": "a lot"
        })
    property bool enabled: true

    function correct(word) {
        if (!enabled || !word || word.length === 0)
            return word;

        var lowerWord = word.toLowerCase();
        if (commonTypos.hasOwnProperty(lowerWord)) {
            var correction = commonTypos[lowerWord];
            Logger.info("AutoCorrect", "Correcting '" + word + "' to '" + correction + "'");
            return correction;
        }
        if (!Dictionary.hasWord(lowerWord)) {
            var suggestions = Dictionary.predict(lowerWord);
            if (suggestions.length > 0) {
                var bestMatch = suggestions[0];
                var distance = levenshteinDistance(lowerWord, bestMatch.toLowerCase());
                if (distance <= 2) {
                    Logger.info("AutoCorrect", "Correcting '" + word + "' to '" + bestMatch + "' (distance: " + distance + ")");
                    return bestMatch;
                }
            }
        }
        return word;
    }

    function levenshteinDistance(a, b) {
        if (a.length === 0)
            return b.length;

        if (b.length === 0)
            return a.length;

        var matrix = [];
        for (var i = 0; i <= b.length; i++)
            matrix[i] = [i];
        for (var j = 0; j <= a.length; j++)
            matrix[0][j] = j;
        for (var i = 1; i <= b.length; i++) {
            for (var j = 1; j <= a.length; j++) {
                if (b.charAt(i - 1) === a.charAt(j - 1))
                    matrix[i][j] = matrix[i - 1][j - 1];
                else
                    matrix[i][j] = Math.min(matrix[i - 1][j - 1] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j] + 1);
            }
        }
        return matrix[b.length][a.length];
    }

    function shouldCorrect(word) {
        if (!enabled || !word || word.length < 3)
            return null;

        var corrected = correct(word);
        if (corrected !== word)
            return corrected;

        return null;
    }

    function learnCorrection(typo, correction) {
        commonTypos[typo.toLowerCase()] = correction;
        Logger.info("AutoCorrect", "Learned: '" + typo + "' -> '" + correction + "'");
    }
}
