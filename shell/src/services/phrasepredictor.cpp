#include "phrasepredictor.h"

PhrasePredictor::PhrasePredictor(QObject *parent)
    : QObject(parent) {
    m_phraseMap.insert("how are", {"you", "you doing", "things"});
    m_phraseMap.insert("how is", {"it going", "everything", "your day"});
    m_phraseMap.insert("what are", {"you doing", "you up to", "your plans"});
    m_phraseMap.insert("what is", {"up", "going on", "your name"});
    m_phraseMap.insert("where are", {"you", "we going", "we meeting"});
    m_phraseMap.insert("where is", {"it", "that", "everyone"});
    m_phraseMap.insert("when are", {"you coming", "we meeting", "you free"});
    m_phraseMap.insert("when is", {"it", "the meeting", "your birthday"});
    m_phraseMap.insert("i am", {"here", "coming", "on my way", "good", "fine"});
    m_phraseMap.insert("i will", {"be there", "call you", "let you know", "do it"});
    m_phraseMap.insert("i have", {"to go", "a question", "an idea", "time"});
    m_phraseMap.insert("i think", {"so", "that", "it's good", "we should"});
    m_phraseMap.insert("i need", {"to", "help", "more time", "your help"});
    m_phraseMap.insert("i want", {"to", "that", "it", "one"});
    m_phraseMap.insert("i hope", {"so", "you're well", "it works", "to see you"});
    m_phraseMap.insert("i love", {"you", "it", "this", "that"});
    m_phraseMap.insert("i like", {"it", "that", "this", "your idea"});
    m_phraseMap.insert("can you", {"help", "do it", "send me", "call me"});
    m_phraseMap.insert("can i", {"help", "ask you", "call you", "come"});
    m_phraseMap.insert("do you", {"know", "have", "want", "think"});
    m_phraseMap.insert("did you", {"get it", "see that", "hear", "know"});
    m_phraseMap.insert("are you", {"there", "coming", "ok", "sure", "free"});
    m_phraseMap.insert("is it", {"ok", "possible", "working", "done"});
    m_phraseMap.insert("let me", {"know", "think", "check", "see"});
    m_phraseMap.insert("thank you", {"so much", "very much", "for everything"});
    m_phraseMap.insert("thanks for", {"your help", "letting me know", "everything"});
    m_phraseMap.insert("looking forward", {"to it", "to hearing", "to seeing you"});
    m_phraseMap.insert("nice to", {"meet you", "see you", "hear from you"});
    m_phraseMap.insert("have a", {"good day", "nice day", "great day", "good one"});
    m_phraseMap.insert("see you", {"later", "soon", "tomorrow", "there"});
    m_phraseMap.insert("talk to", {"you later", "you soon", "me"});
    m_phraseMap.insert("on my", {"way", "phone", "computer", "mind"});
    m_phraseMap.insert("be right", {"back", "there", "over"});
    m_phraseMap.insert("going to", {"be", "do", "the", "try"});
    m_phraseMap.insert("want to", {"go", "do", "see", "try", "know"});
    m_phraseMap.insert("need to", {"go", "do", "talk", "know", "finish"});
    m_phraseMap.insert("have to", {"go", "do", "leave", "work"});
    m_phraseMap.insert("got to", {"go", "run", "do"});
    m_phraseMap.insert("good to", {"know", "see you", "hear"});
    m_phraseMap.insert("great to", {"see you", "hear", "meet you"});
    m_phraseMap.insert("happy to", {"help", "hear", "see you", "know"});
    m_phraseMap.insert("sorry for", {"the delay", "the wait", "bothering you"});
    m_phraseMap.insert("sorry i", {"missed", "forgot", "can't", "didn't"});
    m_phraseMap.insert("no problem", {"at all", "happy to help"});
    m_phraseMap.insert("sounds good", {"to me", "let's do it"});
    m_phraseMap.insert("that sounds", {"good", "great", "perfect", "fun"});
    m_phraseMap.insert("that's a", {"good idea", "great idea", "good point"});
    m_phraseMap.insert("that's great", {"news", "to hear"});
    m_phraseMap.insert("the best", {"way", "thing", "option", "part"});
    m_phraseMap.insert("a lot", {"of", "more", "better"});
    m_phraseMap.insert("of course", {"not", "I will", "you can"});
    m_phraseMap.insert("by the", {"way", "time", "end"});
    m_phraseMap.insert("at the", {"moment", "end", "same time"});
    m_phraseMap.insert("in the", {"morning", "afternoon", "evening", "end"});
    m_phraseMap.insert("on the", {"way", "phone", "other hand"});
}

QStringList PhrasePredictor::getPhrases(const QString &words) const {
    const QString key = words.toLower().trimmed();
    if (m_phraseMap.contains(key)) {
        return m_phraseMap.value(key);
    }

    const QStringList parts = key.split(" ", Qt::SkipEmptyParts);
    if (parts.size() >= 2) {
        const QString lastTwo = parts.mid(parts.size() - 2).join(" ");
        if (m_phraseMap.contains(lastTwo)) {
            return m_phraseMap.value(lastTwo);
        }
    }
    return {};
}

QString PhrasePredictor::getTopPhrase(const QString &words) const {
    const QStringList phrases = getPhrases(words);
    return phrases.isEmpty() ? QString() : phrases.first();
}
