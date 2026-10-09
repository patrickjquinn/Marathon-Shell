// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// See qt5source.h.

#include "qt5source.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QLoggingCategory>
#include <QMutex>
#include <QMutexLocker>
#include <QObject>
#include <QPointer>
#include <QQmlAbstractUrlInterceptor>
#include <QQmlEngine>
#include <QSaveFile>
#include <QStandardPaths>

#include <vector>

Q_LOGGING_CATEGORY(lcQt5Source, "keel.qt5compat.source", QtInfoMsg)

namespace KeelQt5Compat {

namespace {

// Part of the cache key: bump when the rewrite changes what it produces.
constexpr char kRewriteVersion[] = "keel-qt5source-1";

// --- Tokenizer -----------------------------------------------------------
//
// Enough of ECMAScript's lexical grammar to find tokens in QML and
// JavaScript files: identifiers (and keywords), numbers, string literals,
// template literals (with code in ${...} tokenized as code), regular
// expression literals, comments and punctuators. QML's own syntax uses the
// same tokens. A `/` starts a regular expression unless the previous token
// ends an operand (the usual heuristic, as in Qt's own lexer).

enum class Kind { Ident, Number, String, Template, Regex, Punct };

struct Token
{
    Kind kind;
    int start;
    int end;
    bool newlineBefore;
};

bool isIdentStart(QChar c)
{
    return c.isLetter() || c == u'_' || c == u'$' || c == u'\\' || c.unicode() > 0x7f;
}

bool isIdentPart(QChar c)
{
    return isIdentStart(c) || c.isDigit() || c.unicode() == 0x200c || c.unicode() == 0x200d;
}

class Lexer
{
public:
    explicit Lexer(QStringView s)
        : m_s(s)
    {
    }

    std::vector<Token> run()
    {
        // Brace depths at which a template literal's ${ ... } ends.
        std::vector<int> templateDepths;
        int braceDepth = 0;
        bool newline = false;
        const int n = static_cast<int>(m_s.size());
        int i = 0;
        while (i < n) {
            const QChar c = m_s[i];
            if (c == u'\n' || c == u'\r' || c.unicode() == 0x2028 || c.unicode() == 0x2029) {
                newline = true;
                ++i;
                continue;
            }
            if (c.isSpace() || c.unicode() == 0xfeff) {
                ++i;
                continue;
            }
            if (c == u'/' && i + 1 < n && m_s[i + 1] == u'/') {
                while (i < n && m_s[i] != u'\n' && m_s[i] != u'\r')
                    ++i;
                continue;
            }
            if (c == u'/' && i + 1 < n && m_s[i + 1] == u'*') {
                const int close = static_cast<int>(m_s.indexOf(u"*/", i + 2));
                const int end = close < 0 ? n : close + 2;
                for (int k = i; k < end; ++k) {
                    if (m_s[k] == u'\n' || m_s[k] == u'\r')
                        newline = true; // a multi-line comment counts as a line break
                }
                i = end;
                continue;
            }
            const int start = i;
            Kind kind = Kind::Punct;
            if (isIdentStart(c)) {
                while (i < n && isIdentPart(m_s[i])) {
                    if (m_s[i] == u'\\' && i + 1 < n)
                        ++i; // \uXXXX escape
                    ++i;
                }
                kind = Kind::Ident;
            } else if (c.isDigit() || (c == u'.' && i + 1 < n && m_s[i + 1].isDigit())) {
                while (i < n && (m_s[i].isLetterOrNumber() || m_s[i] == u'.' || m_s[i] == u'_'
                                 || ((m_s[i] == u'+' || m_s[i] == u'-')
                                     && (m_s[i - 1] == u'e' || m_s[i - 1] == u'E')
                                     && !m_s.mid(start, i - start).startsWith(u"0x", Qt::CaseInsensitive))))
                    ++i;
                kind = Kind::Number;
            } else if (c == u'"' || c == u'\'') {
                ++i;
                while (i < n && m_s[i] != c && m_s[i] != u'\n') {
                    if (m_s[i] == u'\\')
                        ++i;
                    ++i;
                }
                i = qMin(i + 1, n);
                kind = Kind::String;
            } else if (c == u'`' || (c == u'}' && !templateDepths.empty() && templateDepths.back() == braceDepth)) {
                // A template literal, or its continuation after ${ ... }:
                // up to the closing backtick or the next ${.
                if (c == u'}')
                    templateDepths.pop_back();
                ++i;
                while (i < n) {
                    const QChar t = m_s[i];
                    if (t == u'\\') {
                        i += 2;
                        continue;
                    }
                    if (t == u'`') {
                        ++i;
                        break;
                    }
                    if (t == u'$' && i + 1 < n && m_s[i + 1] == u'{') {
                        i += 2;
                        templateDepths.push_back(braceDepth);
                        break;
                    }
                    ++i;
                }
                i = qMin(i, n);
                kind = Kind::Template;
            } else if (c == u'/' && regexAllowed()) {
                ++i;
                bool inClass = false;
                while (i < n && m_s[i] != u'\n') {
                    const QChar r = m_s[i];
                    if (r == u'\\') {
                        i += 2;
                        continue;
                    }
                    if (r == u'[')
                        inClass = true;
                    else if (r == u']')
                        inClass = false;
                    else if (r == u'/' && !inClass)
                        break;
                    ++i;
                }
                i = qMin(i + 1, n);
                while (i < n && isIdentPart(m_s[i]))
                    ++i; // flags
                kind = Kind::Regex;
            } else {
                i += punctuatorLength(i);
                kind = Kind::Punct;
                if (c == u'{')
                    ++braceDepth;
                else if (c == u'}')
                    --braceDepth;
            }
            m_tokens.push_back({kind, start, qMin(i, n), newline});
            newline = false;
        }
        return std::move(m_tokens);
    }

private:
    int punctuatorLength(int i) const
    {
        static const char16_t *const kPunctuators[] = {
            u">>>=", u"...", u"===", u"!==", u"**=", u"<<=", u">>=", u">>>", u"&&=", u"||=", u"?\?=",
            u"=>", u"==", u"!=", u"<=", u">=", u"&&", u"||", u"??", u"?.", u"++", u"--", u"+=", u"-=",
            u"*=", u"/=", u"%=", u"&=", u"|=", u"^=", u"<<", u">>", u"**"};
        const QStringView rest = m_s.mid(i);
        for (const char16_t *p : kPunctuators) {
            const QStringView punct(p);
            if (rest.startsWith(punct)) {
                // `a?.5:b` is a conditional, not optional chaining.
                if (punct == u"?." && rest.size() > 2 && rest[2].isDigit())
                    continue;
                return static_cast<int>(punct.size());
            }
        }
        return 1;
    }

    bool regexAllowed() const
    {
        if (m_tokens.empty())
            return true;
        const Token &t = m_tokens.back();
        const QStringView text = m_s.mid(t.start, t.end - t.start);
        switch (t.kind) {
        case Kind::Number:
        case Kind::String:
        case Kind::Template:
        case Kind::Regex:
            return false;
        case Kind::Ident: {
            static const char16_t *const kBeforeExpression[] = {
                u"return", u"typeof", u"instanceof", u"in", u"of", u"new", u"delete", u"void",
                u"throw", u"case", u"do", u"else", u"yield", u"await"};
            for (const char16_t *k : kBeforeExpression) {
                if (text == QStringView(k))
                    return true;
            }
            return false;
        }
        case Kind::Punct:
            return !(text == u")" || text == u"]" || text == u"++" || text == u"--");
        }
        return true;
    }

    QStringView m_s;
    std::vector<Token> m_tokens;
};

// --- The rewrite ---------------------------------------------------------

class ConstRewriter
{
public:
    ConstRewriter(QStringView s, const std::vector<Token> &tokens)
        : m_s(s)
        , m_t(tokens)
    {
    }

    // Token indices of `const` keywords to replace with `var`.
    std::vector<int> run() const
    {
        std::vector<int> out;
        for (int i = 0; i < static_cast<int>(m_t.size()); ++i) {
            if (m_t[i].kind == Kind::Ident && is(i, u"const") && needsRewrite(i))
                out.push_back(i);
        }
        return out;
    }

private:
    QStringView text(int i) const { return m_s.mid(m_t[i].start, m_t[i].end - m_t[i].start); }
    bool valid(int i) const { return i >= 0 && i < static_cast<int>(m_t.size()); }
    bool is(int i, QStringView s) const { return valid(i) && text(i) == s; }
    bool isPunct(int i, QStringView s) const { return valid(i) && m_t[i].kind == Kind::Punct && text(i) == s; }

    bool needsRewrite(int i) const
    {
        // `a.const`, `a?.const`, `{ const: 1 }`, `const(...)`: not a declaration.
        if (isPunct(i - 1, u".") || isPunct(i - 1, u"?."))
            return false;
        const bool bindingFollows = valid(i + 1)
            && (m_t[i + 1].kind == Kind::Ident || isPunct(i + 1, u"{") || isPunct(i + 1, u"["));
        if (!bindingFollows)
            return false;
        const bool forHead = isPunct(i - 1, u"(") && (is(i - 2, u"for") || (is(i - 2, u"await") && is(i - 3, u"for")));
        bool missingInitializer = false;
        int j = i + 1;
        for (;;) {
            // The binding: an identifier or a destructuring pattern.
            if (!valid(j))
                return false;
            if (m_t[j].kind == Kind::Ident) {
                ++j;
            } else if (isPunct(j, u"{") || isPunct(j, u"[")) {
                j = skipBalanced(j);
                if (j < 0)
                    return false;
            } else {
                return false;
            }
            if (forHead && (is(j, u"of") || is(j, u"in")))
                return false; // for (const x of y), for (const k in o): valid
            if (isPunct(j, u"=")) {
                j = skipInitializer(j + 1);
            } else {
                missingInitializer = true;
            }
            if (isPunct(j, u",")) {
                ++j;
                continue;
            }
            break;
        }
        return missingInitializer;
    }

    // Index after the bracket that closes the one at `open`, or -1.
    int skipBalanced(int open) const
    {
        int depth = 0;
        for (int k = open; valid(k); ++k) {
            if (m_t[k].kind != Kind::Punct)
                continue;
            const QStringView p = text(k);
            if (p == u"(" || p == u"[" || p == u"{")
                ++depth;
            else if (p == u")" || p == u"]" || p == u"}") {
                if (--depth == 0)
                    return k + 1;
            }
        }
        return -1;
    }

    bool endsOperand(int k) const
    {
        if (!valid(k))
            return false;
        switch (m_t[k].kind) {
        case Kind::Ident:
            return !(is(k, u"return") || is(k, u"typeof") || is(k, u"new") || is(k, u"delete")
                     || is(k, u"void") || is(k, u"in") || is(k, u"of") || is(k, u"instanceof"));
        case Kind::Number:
        case Kind::String:
        case Kind::Template:
        case Kind::Regex:
            return true;
        case Kind::Punct:
            return isPunct(k, u")") || isPunct(k, u"]") || isPunct(k, u"}");
        }
        return false;
    }

    // Tokens that continue an expression on the next line (no automatic
    // semicolon before them).
    bool continuesExpression(int k) const
    {
        if (m_t[k].kind == Kind::Punct)
            return !(isPunct(k, u"{") || isPunct(k, u"++") || isPunct(k, u"--") || isPunct(k, u"!") || isPunct(k, u"~"));
        if (m_t[k].kind == Kind::Template)
            return true; // a tagged template
        return is(k, u"in") || is(k, u"of") || is(k, u"instanceof");
    }

    // From the first token of an initializer: the index of the `,` that
    // separates the next declarator, or of the first token after the
    // declaration.
    int skipInitializer(int k) const
    {
        int depth = 0;
        for (; valid(k); ++k) {
            if (depth == 0 && m_t[k].newlineBefore && endsOperand(k - 1) && !continuesExpression(k))
                return k; // automatic semicolon
            if (m_t[k].kind != Kind::Punct)
                continue;
            const QStringView p = text(k);
            if (p == u"(" || p == u"[" || p == u"{") {
                ++depth;
            } else if (p == u")" || p == u"]" || p == u"}") {
                if (--depth < 0)
                    return k;
            } else if (depth == 0 && (p == u"," || p == u";")) {
                return k;
            }
        }
        return k;
    }

    QStringView m_s;
    const std::vector<Token> &m_t;
};

// --- The interceptor -------------------------------------------------------

QString cacheRoot()
{
    QStringList candidates;
    const QString overridden = qEnvironmentVariable("KEEL_QT5COMPAT_CACHE");
    if (!overridden.isEmpty())
        candidates << overridden;
    candidates << QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
                      + QStringLiteral("/keel/qt5compat");
    const QString appCache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (!appCache.isEmpty())
        candidates << appCache + QStringLiteral("/keel-qt5compat");
    candidates << QDir::tempPath() + QStringLiteral("/keel-qt5compat-")
                      + QString::fromLocal8Bit(qgetenv("USER"));
    for (const QString &dir : std::as_const(candidates)) {
        if (dir.startsWith(QLatin1Char('/')) && QDir().mkpath(dir) && QFileInfo(dir).isWritable())
            return dir;
    }
    return QString();
}

class SourceCompat : public QObject, public QQmlAbstractUrlInterceptor
{
public:
    explicit SourceCompat(QQmlEngine *engine)
        : QObject(engine)
    {
        setObjectName(QStringLiteral("KeelQt5CompatSource"));
    }

    void addRoots(const QStringList &roots)
    {
        QMutexLocker lock(&m_mutex);
        for (const QString &root : roots) {
            QString canonical = QFileInfo(root).canonicalFilePath();
            if (canonical.isEmpty())
                canonical = QDir::cleanPath(QDir(root).absolutePath());
            if (!canonical.endsWith(QLatin1Char('/')))
                canonical += QLatin1Char('/');
            if (!m_roots.contains(canonical))
                m_roots << canonical;
        }
    }

    QList<RewrittenFile> rewritten() const
    {
        QMutexLocker lock(&m_mutex);
        return m_rewritten;
    }

    // May run on Qt's type loader thread.
    QUrl intercept(const QUrl &url, DataType type) override
    {
        if ((type != QmlFile && type != JavaScriptFile) || !url.isLocalFile())
            return url;
        const QString path = url.toLocalFile();
        const QFileInfo info(path);
        QMutexLocker lock(&m_mutex);
        if (!underRoot(info))
            return url;
        const QString key = info.absoluteFilePath();
        const auto cached = m_decisions.constFind(key);
        if (cached != m_decisions.constEnd() && cached->modified == info.lastModified()
            && cached->size == info.size())
            return cached->target.isEmpty() ? url : QUrl::fromLocalFile(cached->target);

        Decision d{info.lastModified(), info.size(), QString()};
        QFile file(path);
        if (file.open(QIODevice::ReadOnly)) {
            const QByteArray bytes = file.readAll();
            // Fast path: nothing to rewrite unless the file mentions `const`.
            if (bytes.contains("const")) {
                const SourceRewrite r = rewriteQt5Source(QString::fromUtf8(bytes));
                if (r.changed())
                    d.target = store(info, bytes, r);
            }
        }
        m_decisions.insert(key, d);
        return d.target.isEmpty() ? url : QUrl::fromLocalFile(d.target);
    }

private:
    struct Decision
    {
        QDateTime modified;
        qint64 size;
        QString target;
    };

    bool underRoot(const QFileInfo &info) const
    {
        QString canonical = info.canonicalFilePath();
        if (canonical.isEmpty())
            return false;
        for (const QString &root : m_roots) {
            if (canonical.startsWith(root))
                return true;
        }
        return false;
    }

    QString store(const QFileInfo &info, const QByteArray &original, const SourceRewrite &r)
    {
        if (m_cacheRoot.isNull())
            m_cacheRoot = cacheRoot();
        if (m_cacheRoot.isEmpty()) {
            qCWarning(lcQt5Source, "%s: Qt 5 source needs a rewrite for Qt 6, but no cache directory is writable",
                      qPrintable(info.absoluteFilePath()));
            return QString();
        }
        QCryptographicHash hash(QCryptographicHash::Sha256);
        hash.addData(kRewriteVersion);
        hash.addData(original);
        // Content-addressed: the directory is the hash, the file keeps its
        // name (Qt tells scripts from modules by the extension).
        const QString dir = m_cacheRoot + QLatin1Char('/') + QString::fromLatin1(hash.result().toHex().left(32));
        QString target = dir + QLatin1Char('/') + info.fileName();
        if (!QFileInfo::exists(target)) {
            QSaveFile out(target);
            if (!QDir().mkpath(dir) || !out.open(QIODevice::WriteOnly)
                || out.write(r.source.toUtf8()) < 0 || !out.commit()) {
                qCWarning(lcQt5Source, "%s: cannot write the Qt 6 rewrite to %s",
                          qPrintable(info.absoluteFilePath()), qPrintable(target));
                return QString();
            }
        }
        qCInfo(lcQt5Source, "%s: %d Qt 5 `const` declaration(s) without initializer loaded as `var` (Qt 6 "
                            "rejects them); compiled from %s",
               qPrintable(info.absoluteFilePath()), r.constDeclarations, qPrintable(target));
        m_rewritten.append({QUrl::fromLocalFile(info.absoluteFilePath()), target, r.constDeclarations});
        return target;
    }

    mutable QMutex m_mutex;
    QStringList m_roots;
    QHash<QString, Decision> m_decisions;
    QList<RewrittenFile> m_rewritten;
    QString m_cacheRoot;
};

SourceCompat *findCompat(const QQmlEngine *engine)
{
    // SourceCompat has no Q_OBJECT, so findChild<SourceCompat *> is refused
    // (Qt 6.6+ static_asserts on it); match the named child and cast instead.
    if (!engine)
        return nullptr;
    for (QObject *child : engine->children()) {
        if (child->objectName() == QLatin1String("KeelQt5CompatSource"))
            return dynamic_cast<SourceCompat *>(child);
    }
    return nullptr;
}

} // namespace

SourceRewrite rewriteQt5Source(QStringView source)
{
    SourceRewrite result;
    const std::vector<Token> tokens = Lexer(source).run();
    const std::vector<int> consts = ConstRewriter(source, tokens).run();
    result.source = source.toString();
    // `const` -> `var  `: same length, so lines and columns do not move.
    for (int i : consts)
        result.source.replace(tokens[i].start, 5, QStringLiteral("var  "));
    result.constDeclarations = static_cast<int>(consts.size());
    return result;
}

bool sourceCompatEnabled()
{
    return qEnvironmentVariable("KEEL_QT5COMPAT_SOURCE") != QLatin1String("0");
}

void installSourceCompat(QQmlEngine *engine, const QStringList &appRoots)
{
    if (!engine || appRoots.isEmpty() || !sourceCompatEnabled())
        return;
    SourceCompat *compat = findCompat(engine);
    if (!compat) {
        compat = new SourceCompat(engine);
        engine->addUrlInterceptor(compat);
    }
    compat->addRoots(appRoots);
}

QList<RewrittenFile> rewrittenFiles(const QQmlEngine *engine)
{
    const SourceCompat *compat = findCompat(engine);
    return compat ? compat->rewritten() : QList<RewrittenFile>();
}

} // namespace KeelQt5Compat
