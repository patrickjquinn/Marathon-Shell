pragma Singleton
import QtQuick

QtObject {
    id: phrasePredictor

    readonly property var phraseMap: ({
            "how are": ["you", "you doing", "things"],
            "how is": ["it going", "everything", "your day"],
            "what are": ["you doing", "you up to", "your plans"],
            "what is": ["up", "going on", "your name"],
            "where are": ["you", "we going", "we meeting"],
            "where is": ["it", "that", "everyone"],
            "when are": ["you coming", "we meeting", "you free"],
            "when is": ["it", "the meeting", "your birthday"],
            "i am": ["here", "coming", "on my way", "good", "fine"],
            "i will": ["be there", "call you", "let you know", "do it"],
            "i have": ["to go", "a question", "an idea", "time"],
            "i think": ["so", "that", "it's good", "we should"],
            "i need": ["to", "help", "more time", "your help"],
            "i want": ["to", "that", "it", "one"],
            "i hope": ["so", "you're well", "it works", "to see you"],
            "i love": ["you", "it", "this", "that"],
            "i like": ["it", "that", "this", "your idea"],
            "can you": ["help", "do it", "send me", "call me"],
            "can i": ["help", "ask you", "call you", "come"],
            "do you": ["know", "have", "want", "think"],
            "did you": ["get it", "see that", "hear", "know"],
            "are you": ["there", "coming", "ok", "sure", "free"],
            "is it": ["ok", "possible", "working", "done"],
            "let me": ["know", "think", "check", "see"],
            "thank you": ["so much", "very much", "for everything"],
            "thanks for": ["your help", "letting me know", "everything"],
            "looking forward": ["to it", "to hearing", "to seeing you"],
            "nice to": ["meet you", "see you", "hear from you"],
            "have a": ["good day", "nice day", "great day", "good one"],
            "see you": ["later", "soon", "tomorrow", "there"],
            "talk to": ["you later", "you soon", "me"],
            "on my": ["way", "phone", "computer", "mind"],
            "be right": ["back", "there", "over"],
            "going to": ["be", "do", "the", "try"],
            "want to": ["go", "do", "see", "try", "know"],
            "need to": ["go", "do", "talk", "know", "finish"],
            "have to": ["go", "do", "leave", "work"],
            "got to": ["go", "run", "do"],
            "good to": ["know", "see you", "hear"],
            "great to": ["see you", "hear", "meet you"],
            "happy to": ["help", "hear", "see you", "know"],
            "sorry for": ["the delay", "the wait", "bothering you"],
            "sorry i": ["missed", "forgot", "can't", "didn't"],
            "no problem": ["at all", "happy to help"],
            "sounds good": ["to me", "let's do it"],
            "that sounds": ["good", "great", "perfect", "fun"],
            "that's a": ["good idea", "great idea", "good point"],
            "that's great": ["news", "to hear"],
            "the best": ["way", "thing", "option", "part"],
            "a lot": ["of", "more", "better"],
            "of course": ["not", "I will", "you can"],
            "by the": ["way", "time", "end"],
            "at the": ["moment", "end", "same time"],
            "in the": ["morning", "afternoon", "evening", "end"],
            "on the": ["way", "phone", "other hand"]
        })

    function getPhrases(words) {
        var key = words.toLowerCase().trim();
        if (phraseMap.hasOwnProperty(key))
            return phraseMap[key];

        var parts = key.split(" ");
        if (parts.length >= 2) {
            var lastTwo = parts.slice(-2).join(" ");
            if (phraseMap.hasOwnProperty(lastTwo))
                return phraseMap[lastTwo];
        }
        return [];
    }

    function getTopPhrase(words) {
        var phrases = getPhrases(words);
        return phrases.length > 0 ? phrases[0] : "";
    }
}
