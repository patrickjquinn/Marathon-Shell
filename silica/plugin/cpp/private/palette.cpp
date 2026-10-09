// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Clean-room; see palette.h.

#include "palette.h"

#include <QHash>
#include <QMetaMethod>

#include <QQmlEngine>

namespace {
// Keel.Ambience property names, in Role order (null: none of its own).
const char *const kAmbienceNames[KeelPalette::RoleCount] = {
    "primaryColor",          "secondaryColor",           "highlightColor",
    "secondaryHighlightColor", "highlightBackgroundColor", "highlightDimmerColor",
    "overlayBackgroundColor", nullptr,                    "errorColor",
};
enum { LightOnDark = 0, DarkOnLight = 1 };

// Keel.Ambience's colours as QColor, read once per change and shared by
// every palette of the engine: Ambience gives them as strings, by name.
class AmbienceCache : public QObject
{
    Q_OBJECT
public:
    explicit AmbienceCache(QObject *ambience)
        : QObject(ambience)
        , m_ambience(ambience)
    {
        connect(ambience, SIGNAL(ambienceChanged()), this, SLOT(refresh()));
        read();
    }

    static AmbienceCache *of(QObject *ambience)
    {
        static QHash<QObject *, AmbienceCache *> caches;
        AmbienceCache *&c = caches[ambience];
        if (!c) {
            c = new AmbienceCache(ambience);
            QObject::connect(ambience, &QObject::destroyed, [ambience] { caches.remove(ambience); });
        }
        return c;
    }

    QColor colors[KeelPalette::RoleCount];
    int scheme = LightOnDark;

signals:
    void changed();

private slots:
    void refresh()
    {
        read();
        emit changed();
    }

private:
    void read()
    {
        for (int r = 0; r < KeelPalette::RoleCount; ++r)
            colors[r] = kAmbienceNames[r] ? QColor(m_ambience->property(kAmbienceNames[r]).toString()) : QColor();
        scheme = m_ambience->property("colorScheme").toInt();
    }

    QObject *m_ambience;
};

// Per metaobject: whether it is a Silica item (declares __keel_silica_style)
// and the notify signal of its `highlighted` (-1: none).
struct SilicaClass
{
    bool silica = false;
    int highlightedNotify = -1;
};

const SilicaClass &silicaClass(const QMetaObject *mo)
{
    static QHash<const QMetaObject *, SilicaClass> classes;
    auto it = classes.constFind(mo);
    if (it != classes.constEnd())
        return *it;
    SilicaClass c;
    c.silica = mo->indexOfProperty("__keel_silica_style") >= 0;
    const int index = mo->indexOfProperty("highlighted");
    if (index >= 0 && mo->property(index).hasNotifySignal())
        c.highlightedNotify = mo->property(index).notifySignalIndex();
    return *classes.insert(mo, c);
}
} // namespace

KeelPalette::KeelPalette(QObject *parent)
    : QObject(parent)
{
}

// The engine of a palette QML created, or of the item that made one itself
// (SilicaText).
static QQmlEngine *engineOf(const QObject *palette)
{
    QQmlEngine *engine = qmlEngine(palette);
    return engine || !palette->parent() ? engine : qmlEngine(palette->parent());
}

void KeelPalette::classBegin()
{
    // The engine is known now, before the bindings that read this palette
    // are first evaluated: they see the ambience's colours at once.
    setEngine(engineOf(this));
}

void KeelPalette::componentComplete()
{
    m_owner = qobject_cast<QQuickItem *>(parent());
    // Bindings that read this palette were evaluated before it completed.
    // Finding the Silica ancestor usually changes none of its colours (the
    // ancestor's are the ambience's too): changed() then would only
    // evaluate them all again.
    QColor before[RoleCount];
    for (int r = 0; r < RoleCount; ++r)
        before[r] = color(Role(r));
    const int schemeBefore = colorScheme();
    m_quiet = true;
    setEngine(engineOf(this));
    resolve();
    m_quiet = false;
    bool same = schemeBefore == colorScheme();
    for (int r = 0; same && r < RoleCount; ++r)
        same = before[r] == color(Role(r));
    if (!same)
        emit changed();
}

static bool isSilicaItem(QObject *object)
{
    return object && silicaClass(object->metaObject()).silica;
}

void KeelPalette::resolve()
{
    for (const auto &c : std::as_const(m_chain))
        disconnect(c);
    m_chain.clear();

    QQuickItem *found = nullptr;
    if (m_owner) {
        m_chain << connect(m_owner, &QQuickItem::parentChanged, this, &KeelPalette::resolve);
        for (QQuickItem *p = m_owner->parentItem(); p; p = p->parentItem()) {
            if (isSilicaItem(p)) {
                found = p;
                break;
            }
            m_chain << connect(p, &QQuickItem::parentChanged, this, &KeelPalette::resolve);
        }
    }
    setParentPalette(found ? found->property("palette").value<KeelPalette *>() : nullptr);
    if (m_silicaParent != found) {
        disconnect(m_highlightConnection);
        m_silicaParent = found;
        if (found) {
            static const int slot = staticMetaObject.indexOfSlot("readParentHighlighted()");
            const int notify = silicaClass(found->metaObject()).highlightedNotify;
            if (notify >= 0)
                m_highlightConnection = QMetaObject::connect(found, notify, this, slot);
        }
    }
    readParentHighlighted();
}

void KeelPalette::readParentHighlighted()
{
    const bool h = m_silicaParent && m_silicaParent->property("highlighted").toBool();
    if (h != m_parentHighlighted) {
        m_parentHighlighted = h;
        emit parentHighlightedChanged();
    }
}

void KeelPalette::setParentPalette(KeelPalette *parent)
{
    if (parent == this)
        parent = nullptr;
    if (m_parent == parent)
        return;
    disconnect(m_parentConnection);
    m_parent = parent;
    if (parent)
        m_parentConnection = connect(parent, &KeelPalette::changed, this, &KeelPalette::changed);
    if (!m_quiet)
        emit changed();
}

void KeelPalette::setEngine(QQmlEngine *engine)
{
    if (m_engine == engine)
        return;
    m_engine = engine;
    m_ambience = nullptr;
    m_cache = nullptr;
    disconnect(m_ambienceConnection);
    if (ambience())
        m_ambienceConnection = connect(static_cast<AmbienceCache *>(m_cache.data()), &AmbienceCache::changed,
                                       this, &KeelPalette::changed);
    if (!m_quiet)
        emit changed();
}

QObject *KeelPalette::ambience() const
{
    if (!m_ambience && m_engine) {
        static int id = -1;
        if (id < 0)
            id = qmlTypeId("Keel", 1, 0, "Ambience");
        if (id >= 0)
            m_ambience = m_engine->singletonInstance<QObject *>(id);
        if (m_ambience)
            m_cache = AmbienceCache::of(m_ambience);
    }
    return m_ambience;
}

int KeelPalette::ambienceScheme() const
{
    return ambience() ? static_cast<AmbienceCache *>(m_cache.data())->scheme : LightOnDark;
}

QColor KeelPalette::ambienceColor(Role role) const
{
    QObject *a = ambience();
    if (role == BackgroundGlowColor)
        role = HighlightColor;
    if (!a) {
        // No engine yet: Keel's dark defaults.
        switch (role) {
        case PrimaryColor: return QColor(255, 255, 255);
        case SecondaryColor: return QColor(255, 255, 255, 153);
        case ErrorColor: return QColor(255, 77, 77);
        case OverlayBackgroundColor: return QColor(0, 0, 0);
        default: return QColor(0, 160, 255);
        }
    }
    return static_cast<AmbienceCache *>(m_cache.data())->colors[role];
}

QColor KeelPalette::derive(const char *function, const QColor &highlight, int scheme) const
{
    QObject *a = ambience();
    if (!a)
        return highlight;
    // By name rather than by signature: the Rust (CXX-Qt) bridge declares the
    // scheme as ::std::int32_t, so "function(QString,int)" names no method
    // (QMetaObject::invokeMethod failed with "No such method").
    const QMetaObject *mo = a->metaObject();
    for (int i = mo->methodOffset(); i < mo->methodCount(); ++i) {
        const QMetaMethod method = mo->method(i);
        if (method.name() != function || method.parameterCount() != 2
            || method.parameterMetaType(1) != QMetaType::fromType<int>())
            continue;
        QString result;
        const QString name = highlight.name(QColor::HexArgb);
        if (method.invoke(a, Qt::DirectConnection, Q_RETURN_ARG(QString, result), Q_ARG(QString, name),
                          Q_ARG(int, scheme)))
            return QColor(result);
        break;
    }
    qWarning("Palette: Ambience has no %s(QString, int)", function);
    return highlight;
}

bool KeelPalette::derivesHighlight() const
{
    return m_set[HighlightColor] || m_schemeSet;
}

bool KeelPalette::derivesScheme() const
{
    return m_schemeSet;
}

int KeelPalette::colorScheme() const
{
    if (m_schemeSet)
        return m_scheme;
    return m_parent ? m_parent->colorScheme() : ambienceScheme();
}

void KeelPalette::setColorScheme(int scheme)
{
    if (m_schemeSet && m_scheme == scheme)
        return;
    m_schemeSet = true;
    m_scheme = scheme;
    emit changed();
}

void KeelPalette::resetColorScheme()
{
    if (!m_schemeSet)
        return;
    m_schemeSet = false;
    emit changed();
}

QColor KeelPalette::color(Role role) const
{
    if (m_set[role])
        return m_colors[role];
    switch (role) {
    case PrimaryColor:
    case SecondaryColor:
        if (derivesScheme()) {
            const bool light = colorScheme() == DarkOnLight;
            const int v = light ? 0 : 255;
            return QColor(v, v, v, role == PrimaryColor ? 255 : 153);
        }
        break;
    case SecondaryHighlightColor:
        if (derivesHighlight())
            return derive("secondaryHighlightFromColor", color(HighlightColor), colorScheme());
        break;
    case HighlightBackgroundColor:
        if (derivesHighlight())
            return derive("highlightBackgroundFromColor", color(HighlightColor), colorScheme());
        break;
    case HighlightDimmerColor:
        if (derivesHighlight())
            return derive("highlightDimmerFromColor", color(HighlightColor), colorScheme());
        break;
    case BackgroundGlowColor:
        if (derivesHighlight())
            return color(HighlightColor);
        break;
    default:
        break;
    }
    return m_parent ? m_parent->color(role) : ambienceColor(role);
}

void KeelPalette::setColor(Role role, const QColor &c)
{
    if (m_set[role] && m_colors[role] == c)
        return;
    m_set[role] = true;
    m_colors[role] = c;
    emit changed();
}

void KeelPalette::resetColor(Role role)
{
    if (!m_set[role])
        return;
    m_set[role] = false;
    emit changed();
}

#include "palette.moc"
