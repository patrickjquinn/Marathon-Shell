/* global React, Icon, Section, Rule */

// ============================================================
// Marathon Design System — Engineering (Qt6 / QML implementation)
// Maps every design token + component to its Qt Quick 6 form.
// ============================================================

// ---------- Code block ----------
function Code({ lang = 'qml', children }) {
  return (
    <pre style={{
      background: 'var(--bb10-deep)',
      border: '1px solid var(--w-04)',
      borderRadius: 4,
      padding: 18,
      margin: '12px 0',
      fontFamily: 'var(--font-mono)',
      fontSize: 12.5,
      lineHeight: 1.6,
      color: 'var(--text-primary)',
      overflowX: 'auto',
      position: 'relative',
    }}>
      <div style={{
        position: 'absolute', top: 10, right: 14,
        fontSize: 10, letterSpacing: 1.4, fontWeight: 700,
        color: 'var(--teal-bright)', textTransform: 'uppercase',
      }}>{lang}</div>
      <code style={{ whiteSpace: 'pre' }}>{children}</code>
    </pre>
  );
}

// ---------- ENGINEERING · Stack ----------
function DSStack() {
  return (
    <Section id="stack" eyebrow="Engineering" title="Stack & tooling" lede="Marathon is written in QML on Qt Quick 6.7 LTS or newer. The system is shipped as a single Qt module exposing one Theme singleton and a flat catalog of Marathon-prefixed QML components (M-prefix). Apps import the module and inherit the system end-to-end.">
      <h3 className="ds-h3">Runtime requirements</h3>
      <div className="ds-spec">
        <div className="ds-spec-row"><div className="k">Qt version</div><div className="v">6.7 LTS minimum · 6.8+ recommended</div><div className="desc">tied to feature deps below</div></div>
        <div className="ds-spec-row"><div className="k">QML imports</div><div className="v">QtQuick · QtQuick.Controls · QtQuick.Layouts · QtQuick.Shapes · QtQuick.Effects</div><div className="desc">core stack</div></div>
        <div className="ds-spec-row"><div className="k">Module</div><div className="v">import dev.marathon.UI 1.0</div><div className="desc">Theme + M-components</div></div>
        <div className="ds-spec-row"><div className="k">Renderer</div><div className="v">RHI — Vulkan on Linux/Wayland</div><div className="desc">QSG_RHI_BACKEND=vulkan</div></div>
        <div className="ds-spec-row"><div className="k">Font loader</div><div className="v">FontLoader · Sora variable + JetBrains Mono</div><div className="desc">bundled QRC</div></div>
        <div className="ds-spec-row"><div className="k">Icons</div><div className="v">SVG via Image · Lucide pack vendored</div><div className="desc">Marathon mark drawn in QtQuick.Shapes</div></div>
        <div className="ds-spec-row"><div className="k">Target</div><div className="v">PostmarketOS · Linux Mobile</div><div className="desc">Wayland session</div></div>
      </div>

      <h3 className="ds-h3">Qt feature dependencies — what we use, what version it lands in</h3>
      <p className="ds-p">Marathon is not portable below Qt 6.7. Each row below shows a Marathon capability and the Qt version that provides its underlying API.</p>
      <div className="ds-spec">
        <div className="ds-spec-row"><div className="k">QtQuick.Effects.MultiEffect</div><div className="v">Qt 6.5+</div><div className="desc">Replaces deprecated Qt5 GraphicalEffects; powers all glass surfaces.</div></div>
        <div className="ds-spec-row"><div className="k">Qt Quick Effect Maker (QQEM)</div><div className="v">Qt 6.5+</div><div className="desc">Tooling for any custom shader beyond MultiEffect.</div></div>
        <div className="ds-spec-row"><div className="k">font.features (OpenType)</div><div className="v">Qt 6.7+</div><div className="desc">font.features: {'{ "tnum": 1 }'} → required for tabular numerics on times, %, $.</div></div>
        <div className="ds-spec-row"><div className="k">Variable font axes</div><div className="v">Qt 6.7+</div><div className="desc">Sora is a variable font; Theme.type.wLight (200) → wBold (700) all from one file.</div></div>
        <div className="ds-spec-row"><div className="k">QtQuick.Shapes ShapePath</div><div className="v">Qt 6.0+</div><div className="desc">Used for the Marathon horizon mark; scales to any size.</div></div>
        <div className="ds-spec-row"><div className="k">enum in QML</div><div className="v">Qt 5.14+ (full in Qt6)</div><div className="desc">MButton.Variant.Primary, etc.</div></div>
      </div>

      <h3 className="ds-h3">Project shape</h3>
      <Code lang="dirtree">{`marathon-ui/
├── qmldir
├── Theme.qml             — singleton: colors, spacing, type, motion
├── MButton.qml           — primary, secondary, ghost, danger
├── MCard.qml             — double-edge stroke + shadow
├── MRow.qml              — 60px list row, icon + text + value
├── MToggle.qml           — 44 × 26 pill, teal-on
├── MSlider.qml           — pill track, white thumb + teal halo
├── MChip.qml             — pill filter chip
├── MAvatar.qml           — monogram + tint
├── MStatusBar.qml        — 28px chrome
├── MTopBar.qml           — 96px large-title
├── MTabBar.qml           — 70px bottom nav
├── MDock.qml             — 64px home gesture row
├── MNowBar.qml           — 36px live activity
├── MActiveFrame.qml      — peeking app tile
├── MDialog.qml           — modal + permission scaffold
├── MHUD.qml              — system overlay
├── MSearchField.qml      — Spotlight prefix
├── MIcon.qml             — Lucide loader
├── MMarathonMark.qml     — horizon glyph (QtQuick.Shapes)
└── effects/
    ├── GlassBg.qml       — backdrop blur wrapper (MultiEffect)
    └── TealGlow.qml      — directional accent halo`}</Code>
    </Section>
  );
}

// ---------- ENGINEERING · Theme singleton ----------
function DSTheme() {
  return (
    <Section id="theme" eyebrow="Engineering" title="Theme singleton" lede="Every Marathon component reads from one pragma-Singleton Theme. Tokens are readonly properties grouped by foundation: color, surface, spacing, radius, type, motion, glass. Apps never hardcode hex; if a value isn't in Theme, it doesn't ship.">
      <Code>{`pragma Singleton
import QtQuick

QtObject {
    id: theme

    // Brand
    readonly property color tealDarkest:  "#006B5D"
    readonly property color tealDark:     "#00897B"
    readonly property color teal:         "#00BFA5"
    readonly property color tealBright:   "#1DE9B6"
    readonly property color tealGlow:     "#5DFFDC"

    // Surfaces
    readonly property color elev0: "#040404"   // black
    readonly property color elev1: "#0A0A0B"
    readonly property color elev2: "#121213"
    readonly property color elev3: "#1C1C1D"
    readonly property color elev4: "#282829"
    readonly property color elev5: "#353536"

    // Text
    readonly property color textPrimary:   "#F5F5F5"
    readonly property color textSecondary: "#6A6A6A"
    readonly property color textTertiary:  "#4A4A4A"
    readonly property color textHint:      "#2A2A2A"
    readonly property color textOnAccent:  "#000000"

    // Secondary — used only where color is semantic
    readonly property color secBlue:   "#3A6B9C"
    readonly property color secGreen:  "#4A8A5E"
    readonly property color secAmber:  "#C89545"
    readonly property color secRose:   "#A85968"
    readonly property color secViolet: "#6B5D8F"

    // Semantic — destructive only
    readonly property color error: "#EF4444"

    // Spacing — 5-point grid
    readonly property QtObject spacing: QtObject {
        readonly property int xs:  5
        readonly property int sm:  10
        readonly property int md:  16
        readonly property int lg:  20
        readonly property int xl:  32
        readonly property int xxl: 40
    }

    // Touch targets
    readonly property QtObject touch: QtObject {
        readonly property int min:   45
        readonly property int small: 60
        readonly property int med:   70
        readonly property int large: 90
    }

    // Radii — Marathon is sharp
    readonly property QtObject radius: QtObject {
        readonly property int none: 0
        readonly property int sm:   2
        readonly property int md:   4    // default
        readonly property int lg:   6
        readonly property int xl:   8
        readonly property int full: 999
        readonly property int squircle: 14   // app icons ONLY
    }

    // Type
    readonly property QtObject type: QtObject {
        readonly property string ui:   "Sora"
        readonly property string mono: "JetBrains Mono"
        readonly property int display: 96
        readonly property int titleL:  48
        readonly property int title1:  34
        readonly property int title2:  28
        readonly property int title3:  22
        readonly property int headline:17
        readonly property int body:    17
        readonly property int callout: 16
        readonly property int subhead: 15
        readonly property int footnote:13
        readonly property int caption: 12
        readonly property int eyebrow: 11
        // Weights — Sora variable
        readonly property int wLight:   200
        readonly property int wReg:     400
        readonly property int wMedium:  500
        readonly property int wSemi:    600
        readonly property int wBold:    700
    }

    // Motion
    readonly property QtObject duration: QtObject {
        readonly property int micro: 80
        readonly property int quick: 160
        readonly property int mod:   240
    }
    readonly property QtObject easing: QtObject {
        // Maps Marathon tokens → Qt6 easing types
        readonly property int std:    Easing.InOutQuad        // --ease-std
        readonly property int dec:    Easing.OutCubic         // --ease-dec
        readonly property int acc:    Easing.InCubic          // --ease-acc
        readonly property int spring: Easing.OutBack          // --ease-spring
    }

    // Glass — top bar / tab bar / Now Bar
    readonly property QtObject glass: QtObject {
        readonly property real titleBlur:  8
        readonly property real chromeBlur: 14
        readonly property real overlayBlur:20
    }
}`}</Code>

      <h3 className="ds-h3">Singleton registration</h3>
      <Code lang="qmldir">{`module dev.marathon.UI
singleton Theme 1.0 Theme.qml
MButton 1.0 MButton.qml
MCard   1.0 MCard.qml
MRow    1.0 MRow.qml
MToggle 1.0 MToggle.qml
...`}</Code>
      <p className="ds-p">Consumers <code>import dev.marathon.UI 1.0</code> and read <code>Theme.teal</code>, <code>Theme.spacing.md</code> directly. No global state, no theme provider tree.</p>
    </Section>
  );
}

// ---------- ENGINEERING · Components ----------
function DSComponentsQML() {
  return (
    <Section id="components-qml" eyebrow="Engineering" title="Components in QML" lede="Each Marathon component is one .qml file, ≤120 lines. Public properties default-mapped to Theme tokens. Inherits Rectangle or Item; never QtQuick.Controls.Button directly — Marathon controls its own surfaces.">
      <h3 className="ds-h3">MButton.qml</h3>
      <Code>{`import QtQuick
import QtQuick.Controls.Basic
import dev.marathon.UI 1.0

Button {
    id: root
    enum Variant { Primary, Secondary, Ghost, Danger }
    property int variant: MButton.Variant.Secondary
    property int size: Theme.touch.min   // 45 default; 38 compact; 50 large

    implicitHeight: size
    leftPadding: 18; rightPadding: 18
    font.family: Theme.type.ui
    font.pixelSize: 14
    font.weight: Theme.type.wSemi
    palette.buttonText: variant === MButton.Variant.Primary ? Theme.textOnAccent
                       : variant === MButton.Variant.Danger ? Theme.error
                       : Theme.textPrimary

    background: Rectangle {
        radius: Theme.radius.md
        gradient: root.variant === MButton.Variant.Primary ? tealGrad : null
        color: root.variant === MButton.Variant.Primary  ? "transparent"
             : root.variant === MButton.Variant.Ghost    ? "transparent"
             :                                             Theme.elev2
        border.width: 1
        border.color: root.variant === MButton.Variant.Primary
                      ? Qt.rgba(0.0, 0.75, 0.65, 0.35) : Qt.rgba(1,1,1,0.08)

        Gradient {
            id: tealGrad
            GradientStop { position: 0.0; color: Theme.tealBright }
            GradientStop { position: 0.5; color: Theme.teal }
            GradientStop { position: 1.0; color: Theme.tealDark }
        }
        Behavior on scale { NumberAnimation {
            duration: Theme.duration.quick; easing.type: Theme.easing.spring
        }}
    }
    onPressedChanged: background.scale = pressed ? 0.96 : 1.0
}`}</Code>

      <h3 className="ds-h3">MRow.qml</h3>
      <Code>{`import QtQuick
import QtQuick.Layouts
import dev.marathon.UI 1.0

Rectangle {
    id: row
    property alias icon: iconImg.source
    property alias title: titleLbl.text
    property alias subtitle: subLbl.text
    property string value: ""
    property bool toggle: false; property bool toggleOn: false
    property bool chev: !toggle && value === ""

    width: parent.width
    height: Math.max(Theme.touch.small, contentRow.implicitHeight + Theme.spacing.md*2)
    color: hover.containsMouse ? Qt.rgba(1,1,1,0.02) : "transparent"

    Rectangle { anchors.left: parent.left; anchors.right: parent.right
                anchors.top: parent.top; height: 1
                color: Qt.rgba(1,1,1,0.04) }

    RowLayout {
        id: contentRow
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.lg
        anchors.rightMargin: Theme.spacing.lg
        spacing: 14

        Rectangle { width: 32; height: 32; radius: Theme.radius.md
                    color: Theme.elev3
                    Image { id: iconImg; anchors.centerIn: parent
                            sourceSize: Qt.size(18, 18) } }

        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            Text { id: titleLbl; color: Theme.textPrimary
                   font { family: Theme.type.ui; pixelSize: 15
                          weight: Theme.type.wMedium; letterSpacing: -0.1 }
                   elide: Text.ElideRight }
            Text { id: subLbl; color: Theme.textSecondary
                   font { family: Theme.type.ui; pixelSize: 13 }
                   visible: text.length > 0; elide: Text.ElideRight }
        }

        Text { text: row.value; color: Theme.textSecondary
               font { family: Theme.type.ui; pixelSize: 14
                      features: { "tnum": 1 } }
               visible: row.value !== "" && !row.toggle }

        MToggle { checked: row.toggleOn; visible: row.toggle }

        MIcon { name: "chevron_right"; size: 16
                color: Theme.textTertiary; visible: row.chev }
    }
    MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true }
}`}</Code>

      <h3 className="ds-h3">MToggle.qml</h3>
      <Code>{`import QtQuick
import dev.marathon.UI 1.0

Rectangle {
    id: tog
    property bool checked: false
    signal toggled()

    width: 44; height: 26; radius: Theme.radius.full
    color: checked ? Theme.teal : Theme.elev3
    border.width: 1
    border.color: checked ? Qt.rgba(0.0, 0.75, 0.65, 0.35) : Qt.rgba(1,1,1,0.04)

    Behavior on color { ColorAnimation {
        duration: Theme.duration.quick; easing.type: Theme.easing.std } }

    layer.enabled: checked
    layer.effect: MultiEffect {
        blurEnabled: false
        shadowEnabled: true
        shadowColor: Qt.rgba(0.11, 0.91, 0.71, 0.18)   // tealHalo
        shadowBlur: 1.0
        shadowVerticalOffset: 0
    }

    Rectangle {
        width: 20; height: 20; radius: Theme.radius.full
        y: 2
        x: tog.checked ? tog.width - width - 2 : 2
        color: tog.checked ? "#FFFFFF" : "#D0D0D0"
        Behavior on x { NumberAnimation {
            duration: Theme.duration.quick; easing.type: Theme.easing.std } }
    }

    MouseArea { anchors.fill: parent
                onClicked: { tog.checked = !tog.checked; tog.toggled() } }
}`}</Code>
    </Section>
  );
}

// ---------- ENGINEERING · Motion ----------
function DSMotionQML() {
  return (
    <Section id="motion-qml" eyebrow="Engineering" title="Motion in Qt6" lede="Every animation declares its duration via Theme.duration and its curve via Theme.easing. Use Behavior on <property> for state changes; NumberAnimation in transitions for property targets. Never SequentialAnimation chained longer than 400ms — keep motion functional.">
      <h3 className="ds-h3">Token → easing-type map</h3>
      <div className="ds-spec">
        <div className="ds-spec-row"><div className="k">--ease-std</div><div className="v">Easing.InOutQuad</div><div className="desc">general UI state change</div></div>
        <div className="ds-spec-row"><div className="k">--ease-dec</div><div className="v">Easing.OutCubic</div><div className="desc">entering — sheet, dialog open</div></div>
        <div className="ds-spec-row"><div className="k">--ease-acc</div><div className="v">Easing.InCubic</div><div className="desc">exiting — sheet, dialog close</div></div>
        <div className="ds-spec-row"><div className="k">--ease-spring</div><div className="v">Easing.OutBack (overshoot 1.7)</div><div className="desc">primary tap response</div></div>
      </div>

      <h3 className="ds-h3">Behaviors</h3>
      <Code>{`Rectangle {
    color: pressed ? Theme.elev3 : Theme.elev2
    Behavior on color { ColorAnimation {
        duration: Theme.duration.quick
        easing.type: Theme.easing.std
    }}
    Behavior on scale { NumberAnimation {
        duration: Theme.duration.quick
        easing.type: Theme.easing.spring
    }}
}`}</Code>

      <h3 className="ds-h3">Page transitions</h3>
      <Code>{`StackView {
    initialItem: HomePage {}
    pushEnter: Transition { NumberAnimation {
        properties: "x"; from: width; to: 0
        duration: Theme.duration.mod; easing.type: Theme.easing.dec }}
    pushExit:  Transition { NumberAnimation {
        properties: "opacity"; from: 1; to: 0
        duration: Theme.duration.quick; easing.type: Theme.easing.acc }}
    popEnter: Transition { NumberAnimation {
        properties: "opacity"; from: 0; to: 1
        duration: Theme.duration.quick; easing.type: Theme.easing.dec }}
    popExit:  Transition { NumberAnimation {
        properties: "x"; from: 0; to: width
        duration: Theme.duration.mod; easing.type: Theme.easing.acc }}
}`}</Code>

      <h3 className="ds-h3">Reduced motion</h3>
      <p className="ds-p">Qt 6 does not expose a system-level "reduce motion" preference through <code>Qt.accessibility</code> — that namespace is for assistive-technology metadata, not motion prefs. Marathon reads the preference from the GNOME/KDE desktop signal on Linux mobile (org.gnome.desktop.interface.enable-animations or kdeglobals KAccessibilityCommon) and exposes it through Theme.motion. Every animation goes through one helper:</p>
      <Code>{`// Theme.qml — exposes a writable, system-fed property.
property bool reduceMotion: false   // bound at app start from
                                     // ApplicationSettings on Linux

readonly property var motion: QtObject {
    function dur(token) {
        return Theme.reduceMotion ? Theme.duration.micro : token
    }
    function ease(token) {
        // Skip overshoot when reduced — OutBack feels jarring.
        return Theme.reduceMotion ? Easing.OutQuad : token
    }
}

// Usage everywhere:
NumberAnimation {
    duration: Theme.motion.dur(Theme.duration.mod)
    easing.type: Theme.motion.ease(Theme.easing.spring)
}`}</Code>
      <p className="ds-p">App init binds <code>Theme.reduceMotion</code> once at startup from the platform: on PostmarketOS / GNOME-Mobile this reads <code>gsettings get org.gnome.desktop.interface enable-animations</code>; on Plasma Mobile it reads <code>kdeglobals.KAccessibilityCommon.skipFancyEffects</code>. C++ side, expose it via QSettings or a small platform shim and assign at root.</p>
    </Section>
  );
}

// ---------- ENGINEERING · Glass & blur ----------
function DSGlass() {
  return (
    <Section id="glass" eyebrow="Engineering" title="Glass surfaces" lede="The status bar, top bar, tab bar, dock, and Now Bar all glass over their parent. In Qt 6.5+, this is done with QtQuick.Effects.MultiEffect — the modern replacement for the Qt5 GraphicalEffects.FastBlur module. One reusable GlassBg.qml wraps the pattern.">
      <Code>{`// GlassBg.qml — wraps a backdrop source and blurs it.
import QtQuick
import QtQuick.Effects
import dev.marathon.UI 1.0

Item {
    id: glass
    property Item sourceItem
    property real blur: Theme.glass.chromeBlur
    property color tint: Qt.rgba(0.05, 0.05, 0.055, 0.78)
    property color borderColor: Qt.rgba(1, 1, 1, 0.06)

    ShaderEffectSource {
        id: snap
        sourceItem: glass.sourceItem
        anchors.fill: parent
        sourceRect: Qt.rect(glass.x, glass.y, glass.width, glass.height)
        live: true; recursive: false
    }
    MultiEffect {
        anchors.fill: parent
        source: snap
        blurEnabled: true
        blur: 1.0
        blurMax: glass.blur
    }
    Rectangle {
        anchors.fill: parent
        color: glass.tint
        border.width: 1
        border.color: glass.borderColor
    }
}`}</Code>

      <h3 className="ds-h3">Usage in MTopBar.qml</h3>
      <Code>{`Item {
    id: bar
    height: 96
    property Item content   // the page beneath, for snapshot

    GlassBg {
        anchors.fill: parent
        sourceItem: bar.content
        blur: Theme.glass.overlayBlur
    }
    // hairline highlight on top edge
    Rectangle { width: parent.width; height: 1
                color: Qt.rgba(1,1,1,0.04) }

    Text {
        anchors.left: parent.left; anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.spacing.lg
        anchors.bottomMargin: 16
        text: bar.title
        color: Theme.textPrimary
        font.family: Theme.type.ui
        font.pixelSize: Theme.type.title1
        font.weight: Theme.type.wLight
        font.letterSpacing: -0.8
    }
}`}</Code>

      <div className="ds-grid cols-2">
        <Rule kind="do" text="Snapshot the backdrop once per layout pass, not per frame. Live: true is fine for scrolling content because MultiEffect runs on GPU."/>
        <Rule kind="dont" text="Don't stack two blurs. If a sheet sits over the top bar, the sheet snapshots the WHOLE composited screen — not the top-bar's already-blurred result."/>
      </div>
    </Section>
  );
}

// ---------- ENGINEERING · Icons & fonts ----------
function DSAssets() {
  return (
    <Section id="assets" eyebrow="Engineering" title="Assets — icons & fonts" lede="Icons are SVG files vendored from Lucide plus one inline Marathon mark drawn in QtQuick.Shapes. Fonts are loaded once at app start. Both are served from QRC (the Qt resource system) so they ship inside the binary.">
      <h3 className="ds-h3">FontLoader — Sora variable + tabular numerics</h3>
      <p className="ds-p">Sora is a variable font with a single 'wght' axis covering 100–800. Qt 6.7+ picks the right cut when you set <code>font.weight</code> — no separate files. Tabular numerics for timestamps, percentages, and prices use OpenType feature <code>tnum</code>, exposed in Qt 6.7+ via <code>font.features</code>.</p>
      <Code>{`// main.qml — load once.
Application {
    FontLoader { source: "qrc:/fonts/Sora[wght].ttf" }
    FontLoader { source: "qrc:/fonts/JetBrainsMono-Medium.ttf" }
}

// Anywhere a numeric reads (clock, %, $) — enable tnum.
Text {
    text: "9:41"
    font.family: Theme.type.ui
    font.pixelSize: Theme.type.display
    font.weight: Theme.type.wLight     // 200, variable
    font.letterSpacing: -3
    font.features: ({ "tnum": 1 })     // requires Qt 6.7+
}`}</Code>

      <h3 className="ds-h3">MIcon.qml — Lucide via SVG</h3>
      <Code>{`import QtQuick
import QtQuick.Effects

Image {
    property string name
    property int size: 20
    property color color: "white"

    width: size; height: size
    sourceSize: Qt.size(size, size)
    source: "qrc:/icons/lucide/" + name + ".svg"

    // Recolor SVG to current color via MultiEffect.
    // Both effects are "always enabled" so no shader cost vs blur.
    layer.enabled: true
    layer.effect: MultiEffect {
        colorization: 1.0
        colorizationColor: parent.color
    }
}`}</Code>

      <h3 className="ds-h3">MMarathonMark.qml — drawn natively, scales to any size</h3>
      <Code>{`import QtQuick
import QtQuick.Shapes
import dev.marathon.UI 1.0

Item {
    id: mark
    property int size: 24
    property color color: Theme.tealBright
    width: size; height: size

    Shape {
        anchors.fill: parent
        // Outer arc — widest horizon
        ShapePath {
            strokeColor: mark.color; strokeWidth: 1.6
            fillColor: "transparent"; capStyle: ShapePath.RoundCap
            startX: 3 * mark.size / 24; startY: 18 * mark.size / 24
            PathQuad { x: 21 * mark.size / 24; y: 18 * mark.size / 24
                       controlX: 12 * mark.size / 24
                       controlY:  4 * mark.size / 24 }
        }
        // (Second arc at 0.75 opacity, third at 0.5,
        //  plus baseline PathLine — same pattern, omitted.)
    }
}`}</Code>
    </Section>
  );
}

// ---------- ENGINEERING · Performance + lifecycle ----------
function DSPerf() {
  return (
    <Section id="perf" eyebrow="Engineering" title="Performance & lifecycle" lede="Marathon targets 60 fps minimum on PostmarketOS reference hardware (Pinephone Pro / OnePlus 6). Three rules keep the system fast.">
      <h3 className="ds-h3">Active Frames lifecycle</h3>
      <p className="ds-p">A peeking Active Frame is a thumbnail render of the app's main view, captured to a <code>ShaderEffectSource</code> at app suspend. The frame's live region polls its model at 1Hz; the rest of the tile is a still snapshot. Never render the full app view on the home grid.</p>
      <Code>{`Item {
    id: frame
    property Item appView           // bound when app is alive
    property url snapshotUrl        // disk-cached when app suspends

    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: frame.appView
        visible: frame.appView !== null
    }
    Image {
        anchors.fill: parent
        source: frame.snapshotUrl
        visible: frame.appView === null
    }
}`}</Code>

      <h3 className="ds-h3">Hot paths</h3>
      <div className="ds-spec">
        <div className="ds-spec-row"><div className="k">Status bar</div><div className="v">single QML, never re-instantiated</div><div className="desc">cached @ window root</div></div>
        <div className="ds-spec-row"><div className="k">List rows</div><div className="v">ListView + delegate, never Repeater</div><div className="desc">recycling above 20 items</div></div>
        <div className="ds-spec-row"><div className="k">Now Bar</div><div className="v">model is shared singleton</div><div className="desc">one source, many surfaces</div></div>
        <div className="ds-spec-row"><div className="k">Wallpaper</div><div className="v">SVG drawn into ShaderEffectSource once</div><div className="desc">never animated</div></div>
        <div className="ds-spec-row"><div className="k">Glass blur</div><div className="v">live: true OK on GPU; cap blur at 20</div><div className="desc">cost is ~constant past 16</div></div>
      </div>

      <h3 className="ds-h3">App state model</h3>
      <Code>{`enum AppState {
    NotRunning,   // not in memory; tap launches cold
    Background,   // suspended, frame snapshot only
    Active        // alive, frame is live render
}`}</Code>
      <p className="ds-p">A user can keep ~8 Active apps before Marathon evicts the oldest. Eviction snapshots the view first so the tile remains tappable — tapping resumes from snapshot until the app rehydrates.</p>
    </Section>
  );
}

Object.assign(window, {
  DSStack, DSTheme, DSComponentsQML, DSMotionQML, DSGlass, DSAssets, DSPerf,
});
