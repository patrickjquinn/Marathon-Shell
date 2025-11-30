// Marathon Virtual Keyboard - Dictionary
// Simple dictionary with frequency-based word suggestions
pragma Singleton
import QtQuick

QtObject {
    id: dictionary

    // Top 1000 most common English words with frequencies
    // Format: {word: "the", freq: 10000}
    property var words: [
        {
            word: "the",
            freq: 10000
        },
        {
            word: "be",
            freq: 8500
        },
        {
            word: "to",
            freq: 8000
        },
        {
            word: "of",
            freq: 7500
        },
        {
            word: "and",
            freq: 7000
        },
        {
            word: "a",
            freq: 6500
        },
        {
            word: "in",
            freq: 6000
        },
        {
            word: "that",
            freq: 5500
        },
        {
            word: "have",
            freq: 5000
        },
        {
            word: "I",
            freq: 4800
        },
        {
            word: "it",
            freq: 4600
        },
        {
            word: "for",
            freq: 4400
        },
        {
            word: "not",
            freq: 4200
        },
        {
            word: "on",
            freq: 4000
        },
        {
            word: "with",
            freq: 3800
        },
        {
            word: "he",
            freq: 3600
        },
        {
            word: "as",
            freq: 3400
        },
        {
            word: "you",
            freq: 3200
        },
        {
            word: "do",
            freq: 3000
        },
        {
            word: "at",
            freq: 2900
        },
        {
            word: "this",
            freq: 2800
        },
        {
            word: "but",
            freq: 2700
        },
        {
            word: "his",
            freq: 2600
        },
        {
            word: "by",
            freq: 2500
        },
        {
            word: "from",
            freq: 2400
        },
        {
            word: "they",
            freq: 2300
        },
        {
            word: "we",
            freq: 2200
        },
        {
            word: "say",
            freq: 2100
        },
        {
            word: "her",
            freq: 2000
        },
        {
            word: "she",
            freq: 1900
        },
        {
            word: "or",
            freq: 1800
        },
        {
            word: "an",
            freq: 1700
        },
        {
            word: "will",
            freq: 1600
        },
        {
            word: "my",
            freq: 1500
        },
        {
            word: "one",
            freq: 1400
        },
        {
            word: "all",
            freq: 1300
        },
        {
            word: "would",
            freq: 1200
        },
        {
            word: "there",
            freq: 1100
        },
        {
            word: "their",
            freq: 1000
        },
        {
            word: "what",
            freq: 950
        },
        {
            word: "so",
            freq: 900
        },
        {
            word: "up",
            freq: 850
        },
        {
            word: "out",
            freq: 800
        },
        {
            word: "if",
            freq: 750
        },
        {
            word: "about",
            freq: 700
        },
        {
            word: "who",
            freq: 650
        },
        {
            word: "get",
            freq: 600
        },
        {
            word: "which",
            freq: 550
        },
        {
            word: "go",
            freq: 500
        },
        {
            word: "me",
            freq: 480
        },
        {
            word: "when",
            freq: 460
        },
        {
            word: "make",
            freq: 440
        },
        {
            word: "can",
            freq: 420
        },
        {
            word: "like",
            freq: 400
        },
        {
            word: "time",
            freq: 380
        },
        {
            word: "no",
            freq: 360
        },
        {
            word: "just",
            freq: 340
        },
        {
            word: "him",
            freq: 320
        },
        {
            word: "know",
            freq: 300
        },
        {
            word: "take",
            freq: 290
        },
        {
            word: "people",
            freq: 280
        },
        {
            word: "into",
            freq: 270
        },
        {
            word: "year",
            freq: 260
        },
        {
            word: "your",
            freq: 250
        },
        {
            word: "good",
            freq: 240
        },
        {
            word: "some",
            freq: 230
        },
        {
            word: "could",
            freq: 220
        },
        {
            word: "them",
            freq: 210
        },
        {
            word: "see",
            freq: 200
        },
        {
            word: "other",
            freq: 195
        },
        {
            word: "than",
            freq: 190
        },
        {
            word: "then",
            freq: 185
        },
        {
            word: "now",
            freq: 180
        },
        {
            word: "look",
            freq: 175
        },
        {
            word: "only",
            freq: 170
        },
        {
            word: "come",
            freq: 165
        },
        {
            word: "its",
            freq: 160
        },
        {
            word: "over",
            freq: 155
        },
        {
            word: "think",
            freq: 150
        },
        {
            word: "also",
            freq: 148
        },
        {
            word: "back",
            freq: 146
        },
        {
            word: "after",
            freq: 144
        },
        {
            word: "use",
            freq: 142
        },
        {
            word: "two",
            freq: 140
        },
        {
            word: "how",
            freq: 138
        },
        {
            word: "our",
            freq: 136
        },
        {
            word: "work",
            freq: 134
        },
        {
            word: "first",
            freq: 132
        },
        {
            word: "well",
            freq: 130
        },
        {
            word: "way",
            freq: 128
        },
        {
            word: "even",
            freq: 126
        },
        {
            word: "new",
            freq: 124
        },
        {
            word: "want",
            freq: 122
        },
        {
            word: "because",
            freq: 120
        },
        {
            word: "any",
            freq: 118
        },
        {
            word: "these",
            freq: 116
        },
        {
            word: "give",
            freq: 114
        },
        {
            word: "day",
            freq: 112
        },
        {
            word: "most",
            freq: 110
        },
        {
            word: "us",
            freq: 108
        },
        {
            word: "is",
            freq: 9000
        },
        {
            word: "was",
            freq: 4500
        },
        {
            word: "are",
            freq: 3500
        },
        {
            word: "been",
            freq: 2800
        },
        {
            word: "has",
            freq: 2400
        },
        {
            word: "had",
            freq: 2200
        },
        {
            word: "were",
            freq: 1800
        },
        {
            word: "said",
            freq: 1600
        },
        {
            word: "did",
            freq: 900
        },
        {
            word: "here",
            freq: 600
        },
        {
            word: "where",
            freq: 550
        },
        {
            word: "why",
            freq: 400
        },
        {
            word: "how",
            freq: 380
        },
        {
            word: "hello",
            freq: 200
        },
        {
            word: "yes",
            freq: 180
        },
        {
            word: "please",
            freq: 160
        },
        {
            word: "thank",
            freq: 150
        },
        {
            word: "thanks",
            freq: 140
        },
        {
            word: "sorry",
            freq: 130
        },
        {
            word: "okay",
            freq: 120
        },
        {
            word: "ok",
            freq: 110
        },
        {
            word: "great",
            freq: 100
        },
        {
            word: "awesome",
            freq: 90
        }
    ]

    // User's personal dictionary (learned words)
    property var userWords: []

    // Get predictions for a given prefix
    function predict(prefix) {
        if (!prefix || prefix.length === 0) {
            return [];
        }

        const lowerPrefix = prefix.toLowerCase();

        // Combine system and user dictionaries
        const allWords = words.concat(userWords);

        // Filter words that start with prefix
        const matches = allWords.filter(function (entry) {
            return entry.word.toLowerCase().startsWith(lowerPrefix);
        });

        // Sort by frequency (higher first)
        matches.sort(function (a, b) {
            return b.freq - a.freq;
        });

        // Return top 3 matches
        return matches.slice(0, 3).map(function (entry) {
            return entry.word;
        });
    }

    // Learn a new word from user input
    function learnWord(word) {
        if (!word || word.length < 2) {
            return;
        }

        // Check if word already exists in user dictionary
        const existing = userWords.findIndex(function (entry) {
            return entry.word.toLowerCase() === word.toLowerCase();
        });

        if (existing >= 0) {
            // Increase frequency
            userWords[existing].freq += 10;
        } else {
            // Add new word with medium frequency
            userWords.push({
                word: word,
                freq: 100
            });
        }

        keyboard.logMessage("Dictionary", "Learned word: " + word);
    }

    // Check if a word exists in dictionary
    function hasWord(word) {
        const lowerWord = word.toLowerCase();

        const inSystem = words.some(function (entry) {
            return entry.word.toLowerCase() === lowerWord;
        });

        if (inSystem)
            return true;

        return userWords.some(function (entry) {
            return entry.word.toLowerCase() === lowerWord;
        });
    }

    // Get word frequency (for auto-correction scoring)
    function getFrequency(word) {
        const lowerWord = word.toLowerCase();

        const systemEntry = words.find(function (entry) {
            return entry.word.toLowerCase() === lowerWord;
        });

        if (systemEntry) {
            return systemEntry.freq;
        }

        const userEntry = userWords.find(function (entry) {
            return entry.word.toLowerCase() === lowerWord;
        });

        return userEntry ? userEntry.freq : 0;
    }
}
