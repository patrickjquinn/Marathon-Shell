pragma Singleton
import QtQuick

Item {
    id: dictionary

    property var cachedPredictions: []
    property string lastPredictionPrefix: ""
    property string lastContext: ""
    readonly property var emojiMap: ({
            "happy": "😀",
            "sad": "😢",
            "love": "❤️",
            "heart": "❤️",
            "laugh": "😂",
            "lol": "😂",
            "cry": "😭",
            "angry": "😠",
            "cool": "😎",
            "great": "👍",
            "thanks": "🙏",
            "thank": "🙏",
            "yes": "👍",
            "no": "👎",
            "ok": "👌",
            "good": "👍",
            "bad": "👎",
            "fire": "🔥",
            "party": "🎉",
            "birthday": "🎂",
            "food": "🍕",
            "pizza": "🍕",
            "coffee": "☕",
            "beer": "🍺",
            "sun": "☀️",
            "rain": "🌧️",
            "snow": "❄️",
            "hot": "🔥",
            "cold": "🥶",
            "music": "🎵",
            "phone": "📱",
            "home": "🏠",
            "work": "💼",
            "sleep": "😴",
            "tired": "😴",
            "think": "🤔",
            "idea": "💡",
            "money": "💰",
            "time": "⏰",
            "star": "⭐",
            "check": "✅",
            "question": "❓",
            "warning": "⚠️",
            "congrats": "🎉",
            "sorry": "😔",
            "please": "🙏",
            "hello": "👋",
            "hi": "👋",
            "bye": "👋",
            "wow": "😮",
            "omg": "😱",
            "haha": "😂",
            "nice": "👍",
            "cute": "🥰",
            "beautiful": "😍",
            "amazing": "🤩",
            "awesome": "🔥",
            "perfect": "💯",
            "dog": "🐕",
            "cat": "🐱"
        })
    readonly property var phraseMap: ({
            "how are": ["you", "you doing", "things"],
            "how is": ["it going", "everything", "your day"],
            "what are": ["you doing", "you up to"],
            "what is": ["up", "going on", "your name"],
            "i am": ["here", "coming", "on my way", "good"],
            "i will": ["be there", "call you", "let you know"],
            "i have": ["to go", "a question", "an idea"],
            "i think": ["so", "that", "it's good"],
            "i need": ["to", "help", "more time"],
            "i want": ["to", "that", "it"],
            "i love": ["you", "it", "this"],
            "i like": ["it", "that", "this"],
            "can you": ["help", "do it", "send me"],
            "can i": ["help", "ask you", "call you"],
            "do you": ["know", "have", "want"],
            "are you": ["there", "coming", "ok", "free"],
            "is it": ["ok", "possible", "working"],
            "let me": ["know", "think", "check"],
            "thank you": ["so much", "very much"],
            "thanks for": ["your help", "letting me know"],
            "looking forward": ["to it", "to hearing"],
            "nice to": ["meet you", "see you"],
            "have a": ["good day", "nice day", "great day"],
            "see you": ["later", "soon", "tomorrow"],
            "talk to": ["you later", "you soon"],
            "on my": ["way", "phone", "mind"],
            "be right": ["back", "there"],
            "going to": ["be", "do", "the"],
            "want to": ["go", "do", "see"],
            "need to": ["go", "do", "talk"],
            "sounds good": ["to me"],
            "that sounds": ["good", "great", "perfect"],
            "no problem": ["at all"]
        })

    function predict(prefix) {
        if (!prefix || prefix.length === 0)
            return [];

        if (typeof WordEngine === 'undefined' || WordEngine === null || !WordEngine.enabled)
            return [];

        if (dictionary.lastPredictionPrefix !== prefix) {
            dictionary.lastPredictionPrefix = prefix;
            dictionary.cachedPredictions = [];
            WordEngine.requestPredictions(prefix, 5);
        }
        return cachedPredictions;
    }

    function getEmojiForWord(word) {
        if (!word)
            return "";

        var lowerWord = word.toLowerCase();
        return emojiMap.hasOwnProperty(lowerWord) ? emojiMap[lowerWord] : "";
    }

    function getPhraseCompletions(context) {
        if (!context)
            return [];

        var lowerContext = context.toLowerCase().trim();
        if (phraseMap.hasOwnProperty(lowerContext))
            return phraseMap[lowerContext];

        var words = lowerContext.split(" ");
        if (words.length >= 2) {
            var lastTwo = words.slice(-2).join(" ");
            if (phraseMap.hasOwnProperty(lastTwo))
                return phraseMap[lastTwo];
        }
        return [];
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
            if (prefix === dictionary.lastPredictionPrefix) {
                var enhanced = predictions.slice();
                var emoji = dictionary.getEmojiForWord(prefix);
                if (emoji && enhanced.length < 5)
                    enhanced.push(emoji);

                dictionary.cachedPredictions = enhanced;
            }
        }

        target: typeof WordEngine !== 'undefined' ? WordEngine : null
    }
}
