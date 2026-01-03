pragma Singleton
import QtQuick

QtObject {
    id: emojiPredictor

    readonly property var emojiMap: ({
            "happy": ["😀", "😊", "😄"],
            "sad": ["😢", "😞", "😔"],
            "love": ["❤️", "😍", "💕"],
            "heart": ["❤️", "💖", "💗"],
            "laugh": ["😂", "🤣", "😆"],
            "lol": ["😂", "🤣", "😄"],
            "cry": ["😢", "😭", "😿"],
            "angry": ["😠", "😡", "🤬"],
            "cool": ["😎", "🆒", "👍"],
            "great": ["👍", "🙌", "✨"],
            "thanks": ["🙏", "👍", "❤️"],
            "thank": ["🙏", "👍", "❤️"],
            "yes": ["👍", "✅", "👌"],
            "no": ["👎", "❌", "🙅"],
            "ok": ["👌", "👍", "✅"],
            "good": ["👍", "👌", "🙌"],
            "bad": ["👎", "😕", "❌"],
            "fire": ["🔥", "💥", "⚡"],
            "party": ["🎉", "🥳", "🎊"],
            "birthday": ["🎂", "🎉", "🎁"],
            "food": ["🍕", "🍔", "🍟"],
            "pizza": ["🍕", "🧀", "🍴"],
            "coffee": ["☕", "🫖", "🍵"],
            "beer": ["🍺", "🍻", "🥂"],
            "sun": ["☀️", "🌞", "🌅"],
            "rain": ["🌧️", "☔", "💧"],
            "snow": ["❄️", "☃️", "🌨️"],
            "hot": ["🔥", "🥵", "☀️"],
            "cold": ["🥶", "❄️", "🧊"],
            "music": ["🎵", "🎶", "🎸"],
            "phone": ["📱", "☎️", "📞"],
            "home": ["🏠", "🏡", "🏘️"],
            "work": ["💼", "🏢", "👔"],
            "sleep": ["😴", "💤", "🛏️"],
            "tired": ["😴", "😩", "🥱"],
            "think": ["🤔", "💭", "🧠"],
            "idea": ["💡", "🧠", "✨"],
            "money": ["💰", "💵", "🤑"],
            "time": ["⏰", "🕐", "⌚"],
            "star": ["⭐", "🌟", "✨"],
            "check": ["✅", "☑️", "✔️"],
            "question": ["❓", "🤔", "❔"],
            "warning": ["⚠️", "🚨", "⛔"],
            "congrats": ["🎉", "👏", "🥳"],
            "sorry": ["😔", "🙏", "😢"],
            "please": ["🙏", "🥺", "😊"],
            "hello": ["👋", "😊", "🙋"],
            "hi": ["👋", "😊", "🙋"],
            "bye": ["👋", "😢", "🙋"],
            "goodbye": ["👋", "😢", "🙋"],
            "wow": ["😮", "🤩", "😲"],
            "omg": ["😱", "😮", "🙀"],
            "haha": ["😂", "🤣", "😆"],
            "nice": ["👍", "👌", "🙌"],
            "cute": ["🥰", "😊", "💕"],
            "beautiful": ["😍", "✨", "💖"],
            "amazing": ["🤩", "😍", "✨"],
            "awesome": ["🔥", "🙌", "✨"],
            "perfect": ["💯", "✨", "👌"],
            "run": ["🏃", "🏃‍♂️", "🏃‍♀️"],
            "walk": ["🚶", "🚶‍♂️", "🚶‍♀️"],
            "car": ["🚗", "🚙", "🏎️"],
            "plane": ["✈️", "🛫", "🛬"],
            "dog": ["🐕", "🐶", "🦮"],
            "cat": ["🐱", "🐈", "😺"],
            "book": ["📖", "📚", "📕"],
            "movie": ["🎬", "🎥", "📽️"],
            "game": ["🎮", "🕹️", "🎯"],
            "win": ["🏆", "🥇", "🎉"],
            "lose": ["😞", "😔", "👎"]
        })

    function getEmojis(word) {
        var lowerWord = word.toLowerCase();
        if (emojiMap.hasOwnProperty(lowerWord))
            return emojiMap[lowerWord];

        return [];
    }

    function getTopEmoji(word) {
        var emojis = getEmojis(word);
        return emojis.length > 0 ? emojis[0] : "";
    }
}
