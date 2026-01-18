#include "emojipredictor.h"

EmojiPredictor::EmojiPredictor(QObject *parent)
    : QObject(parent) {
    m_emojiMap.insert("happy", {"😀", "😊", "😄"});
    m_emojiMap.insert("sad", {"😢", "😞", "😔"});
    m_emojiMap.insert("love", {"❤️", "😍", "💕"});
    m_emojiMap.insert("heart", {"❤️", "💖", "💗"});
    m_emojiMap.insert("laugh", {"😂", "🤣", "😆"});
    m_emojiMap.insert("lol", {"😂", "🤣", "😄"});
    m_emojiMap.insert("cry", {"😢", "😭", "😿"});
    m_emojiMap.insert("angry", {"😠", "😡", "🤬"});
    m_emojiMap.insert("cool", {"😎", "🆒", "👍"});
    m_emojiMap.insert("great", {"👍", "🙌", "✨"});
    m_emojiMap.insert("thanks", {"🙏", "👍", "❤️"});
    m_emojiMap.insert("thank", {"🙏", "👍", "❤️"});
    m_emojiMap.insert("yes", {"👍", "✅", "👌"});
    m_emojiMap.insert("no", {"👎", "❌", "🙅"});
    m_emojiMap.insert("ok", {"👌", "👍", "✅"});
    m_emojiMap.insert("good", {"👍", "👌", "🙌"});
    m_emojiMap.insert("bad", {"👎", "😕", "❌"});
    m_emojiMap.insert("fire", {"🔥", "💥", "⚡"});
    m_emojiMap.insert("party", {"🎉", "🥳", "🎊"});
    m_emojiMap.insert("birthday", {"🎂", "🎉", "🎁"});
    m_emojiMap.insert("food", {"🍕", "🍔", "🍟"});
    m_emojiMap.insert("pizza", {"🍕", "🧀", "🍴"});
    m_emojiMap.insert("coffee", {"☕", "🫖", "🍵"});
    m_emojiMap.insert("beer", {"🍺", "🍻", "🥂"});
    m_emojiMap.insert("sun", {"☀️", "🌞", "🌅"});
    m_emojiMap.insert("rain", {"🌧️", "☔", "💧"});
    m_emojiMap.insert("snow", {"❄️", "☃️", "🌨️"});
    m_emojiMap.insert("hot", {"🔥", "🥵", "☀️"});
    m_emojiMap.insert("cold", {"🥶", "❄️", "🧊"});
    m_emojiMap.insert("music", {"🎵", "🎶", "🎸"});
    m_emojiMap.insert("phone", {"📱", "☎️", "📞"});
    m_emojiMap.insert("home", {"🏠", "🏡", "🏘️"});
    m_emojiMap.insert("work", {"💼", "🏢", "👔"});
    m_emojiMap.insert("sleep", {"😴", "💤", "🛏️"});
    m_emojiMap.insert("tired", {"😴", "😩", "🥱"});
    m_emojiMap.insert("think", {"🤔", "💭", "🧠"});
    m_emojiMap.insert("idea", {"💡", "🧠", "✨"});
    m_emojiMap.insert("money", {"💰", "💵", "🤑"});
    m_emojiMap.insert("time", {"⏰", "🕐", "⌚"});
    m_emojiMap.insert("star", {"⭐", "🌟", "✨"});
    m_emojiMap.insert("check", {"✅", "☑️", "✔️"});
    m_emojiMap.insert("question", {"❓", "🤔", "❔"});
    m_emojiMap.insert("warning", {"⚠️", "🚨", "⛔"});
    m_emojiMap.insert("congrats", {"🎉", "👏", "🥳"});
    m_emojiMap.insert("sorry", {"😔", "🙏", "😢"});
    m_emojiMap.insert("please", {"🙏", "🥺", "😊"});
    m_emojiMap.insert("hello", {"👋", "😊", "🙋"});
    m_emojiMap.insert("hi", {"👋", "😊", "🙋"});
    m_emojiMap.insert("bye", {"👋", "😢", "🙋"});
    m_emojiMap.insert("goodbye", {"👋", "😢", "🙋"});
    m_emojiMap.insert("wow", {"😮", "🤩", "😲"});
    m_emojiMap.insert("omg", {"😱", "😮", "🙀"});
    m_emojiMap.insert("haha", {"😂", "🤣", "😆"});
    m_emojiMap.insert("nice", {"👍", "👌", "🙌"});
    m_emojiMap.insert("cute", {"🥰", "😊", "💕"});
    m_emojiMap.insert("beautiful", {"😍", "✨", "💖"});
    m_emojiMap.insert("amazing", {"🤩", "😍", "✨"});
    m_emojiMap.insert("awesome", {"🔥", "🙌", "✨"});
    m_emojiMap.insert("perfect", {"💯", "✨", "👌"});
    m_emojiMap.insert("run", {"🏃", "🏃‍♂️", "🏃‍♀️"});
    m_emojiMap.insert("walk", {"🚶", "🚶‍♂️", "🚶‍♀️"});
    m_emojiMap.insert("car", {"🚗", "🚙", "🏎️"});
    m_emojiMap.insert("plane", {"✈️", "🛫", "🛬"});
    m_emojiMap.insert("dog", {"🐕", "🐶", "🦮"});
    m_emojiMap.insert("cat", {"🐱", "🐈", "😺"});
    m_emojiMap.insert("book", {"📖", "📚", "📕"});
    m_emojiMap.insert("movie", {"🎬", "🎥", "📽️"});
    m_emojiMap.insert("game", {"🎮", "🕹️", "🎯"});
    m_emojiMap.insert("win", {"🏆", "🥇", "🎉"});
    m_emojiMap.insert("lose", {"😞", "😔", "👎"});
}

QStringList EmojiPredictor::getEmojis(const QString &word) const {
    const QString lowerWord = word.toLower();
    if (m_emojiMap.contains(lowerWord)) {
        return m_emojiMap.value(lowerWord);
    }
    return {};
}

QString EmojiPredictor::getTopEmoji(const QString &word) const {
    const QStringList emojis = getEmojis(word);
    return emojis.isEmpty() ? QString() : emojis.first();
}
