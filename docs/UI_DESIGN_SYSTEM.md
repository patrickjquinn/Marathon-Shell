# Marathon UI Design System

## Philosophy

Marathon UI is a **performance-first, BB10-inspired design system** optimized for embedded systems (Raspberry Pi 4). It emphasizes:

- **Black background with dark grey cards** - Pure OLED-friendly aesthetic
- **Teal accent palette** - Dark teal to bright teal gradient
- **Depth through layers** - Dual-border technique + dynamic elevation
- **Sharp, squared-off aesthetics** with minimal rounded corners (0-4px radius)
- **Spring physics motion** - Natural, fluid animations
- **Opaque-first rendering** for maximum GPU efficiency
- **60fps target** on ARM embedded hardware

---

## Design Tokens

### Colors (`MColors.qml`)

**Background:**
```qml
background: "#000000"         // Pure black (OLED-friendly)
```

**Surface Elevation (Dark Grey Cards):**
```qml
surface0: "#0A0A0A"          // Sunken (inset fields)
surface1: "#1A1A1A"          // Base cards
surface2: "#242424"          // Raised elements
surface3: "#2E2E2E"          // Modals, sheets
surface4: "#383838"          // Floating menus
surface5: "#424242"          // Highest elevation
```

**Teal Accent Palette:**
```qml
accent: "#14B8A6"            // Primary teal
accentBright: "#2DD4BF"      // Bright teal (borders)
accentDim: "#0D9488"         // Dark teal (muted)
accentHover: "#0F766E"       // Hover state
accentPressed: "#0A5F56"     // Pressed state
accentLight: "#5EEAD4"       // Light emphasis
accentSubtle: rgba(0.078, 0.722, 0.651, 0.1)  // 10% tint
```

**Text:**
```qml
text: "#FFFFFF"              // Primary (white)
textSecondary: "#A0A0A0"     // Secondary (light grey)
textTertiary: "#707070"      // Tertiary (medium grey)
textOnAccent: "#000000"      // Text on teal (black)
```

**Semantic Colors:**
```qml
success: "#10B981"  successDim: "#059669"  successBright: "#34D399"
warning: "#F59E0B"  warningDim: "#D97706"  warningBright: "#FBBF24"
error: "#EF4444"    errorDim: "#DC2626"    errorBright: "#F87171"
info: "#3B82F6"     infoDim: "#2563EB"     infoBright: "#60A5FA"
```

### Motion (`MMotion.qml`)

**Duration Tokens:**
```qml
instant: 0
micro: 100          // Hover, ripple start
quick: 200          // Button press, toggle
moderate: 300       // Card animations, sheets
slow: 400           // Modals, page transitions
slower: 600         // Complex choreography
```

**Spring Physics:**
```qml
springLight: 1.5    dampingLight: 0.15     // Bouncy (cards, buttons)
springMedium: 2.0   dampingMedium: 0.25    // Balanced (sheets, modals)
springHeavy: 3.0    dampingHeavy: 0.4      // Firm (toggles, sliders)
```

**Easing Curves:**
```qml
easingStandard: Easing.OutCubic       // Default smooth
easingDecelerate: Easing.OutQuint     // Heavy deceleration
easingAccelerate: Easing.InQuint      // Heavy acceleration
easingEmphasized: Easing.OutExpo      // Dramatic emphasis
easingSharp: Easing.InOutQuad         // BB10-like precision
```

**Choreography (Staggered Delays):**
```qml
staggerMicro: 20      // Tight sequence (list items)
staggerShort: 50      // Standard sequence (card grid)
staggerMedium: 80     // Relaxed sequence
staggerLong: 120      // Dramatic reveal
```

---

## Component Library

### MButton - Primary Interactive Element

**Variants:**
- `primary` - Teal background with white text
- `secondary` - Dark grey card with border
- `tertiary` - Transparent with border
- `ghost` - Transparent, borderless
- `danger` - Red background
- `success` - Green background

**States:**
- `default` - Normal state
- `loading` - Spinner replaces content
- `success` - Checkmark animation
- `error` - X icon animation

**Example:**
```qml
import MarathonUI.Core

MButton {
    text: "Save Changes"
    variant: "primary"
    size: "medium"
    iconName: "check"
    state: "default"  // or "loading", "success", "error"
    onClicked: {
        state = "loading"
        // ...do async work...
        state = "success"
    }
}
```

**Features:**
- ✅ Spring physics press animation (scale: 0.98)
- ✅ Ripple effect on touch
- ✅ Loading/success/error states
- ✅ Dual-border depth
- ✅ Teal accent colors

### MIconButton - Icon-Only Buttons

```qml
MIconButton {
    iconName: "settings"
    variant: "ghost"       // ghost, primary, secondary
    shape: "circular"      // circular, square
    size: Constants.touchTargetMedium
    onClicked: { }
}
```

**Features:**
- ✅ Spring physics press animation
- ✅ Ripple effect
- ✅ Circular or square shapes
- ✅ Consistent with MButton

### MCard - Elevated Containers

```qml
import MarathonUI.Containers

MCard {
    elevation: 1
    elevationHover: 2
    elevationPressed: 0
    interactive: true  // Enables hover/press states
    
    onClicked: { }
    
    content: [
        Text {
            text: "Card content"
            color: MColors.text
        }
    ]
}
```

**Features:**
- ✅ Dynamic elevation (changes on hover/press)
- ✅ Spring physics scale animation
- ✅ Dual-border depth technique
- ✅ Interactive mode for clickable cards

### MRipple - Touch Feedback

```qml
import MarathonUI.Effects

Rectangle {
    // ... your component ...
    
    MRipple {
        id: ripple
        rippleColor: MColors.ripple
    }
    
    MouseArea {
        anchors.fill: parent
        onPressed: function(mouse) {
            ripple.trigger(Qt.point(mouse.x, mouse.y))
        }
    }
}
```

**Features:**
- ✅ Expands from touch point
- ✅ Fades out naturally
- ✅ Configurable color
- ✅ Performance-optimized

### MNavigationPane - Page Transitions

```qml
import MarathonUI.Navigation

MNavigationPane {
    initialPage: homePage
    
    onPagePushed: function(page) { }
    onPagePopped: function(page) { }
}
```

**Features:**
- ✅ Parallax depth (background page shifts 30%)
- ✅ Scale animations (0.95 → 1.0, 1.0 → 0.92)
- ✅ Smooth fade transitions
- ✅ Emphasized easing curves
- ✅ iOS-inspired feel

---

## Depth & Layers

### Dual-Border Technique

All elevated components use a two-border system for depth:

```qml
// Outer border (shadow edge)
border.color: MColors.borderOuter  // Pure black

// Inner border (highlight edge)
Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    border.color: MColors.borderInner  // Subtle white (rgba 5%)
}
```

### Dynamic Elevation

Components respond to interaction:

```qml
// At rest: elevation 1
// On hover: elevation 2 (lift up)
// On press: elevation 0 (push down)

currentElevation: pressed ? 0 : (hovered ? 2 : 1)
```

---

## Motion Design Principles

### 1. Spring Physics Over Linear

❌ **Bad:**
```qml
Behavior on scale {
    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
}
```

✅ **Good:**
```qml
Behavior on scale {
    SpringAnimation { 
        spring: MMotion.springMedium
        damping: MMotion.dampingMedium
        epsilon: MMotion.epsilon
    }
}
```

### 2. Unified Press States

All interactive components follow the same pattern:

```qml
scale: pressed ? 0.98 : 1.0  // Slight push down
color: pressed ? darkerColor : normalColor
```

### 3. Ripple Feedback

Every touch interaction triggers a ripple:

```qml
onPressed: function(mouse) {
    rippleEffect.trigger(Qt.point(mouse.x, mouse.y))
    HapticService.light()
}
```

### 4. State Transitions

State changes are animated, not instant:

```qml
Icon {
    visible: state === "success"
    scale: state === "success" ? 1 : 0
    
    Behavior on scale {
        SpringAnimation { 
            spring: MMotion.springLight
            damping: MMotion.dampingLight
        }
    }
}
```

---

## Performance Principles

### 1. Opaque Rendering First

All UI elements use fully opaque colors (alpha = 1.0) unless absolutely necessary.

**Exceptions:**
- Overlay backgrounds: `MColors.overlay` (85% opacity)
- Glass effects: `MColors.glass` (97% opacity)
- Ripple effects: `MColors.ripple` (12% opacity)
- Accent tints: `MColors.accentSubtle` (10% opacity)

### 2. No layer.enabled (Except Icons)

`layer.enabled` creates expensive framebuffer objects. Only used for icon colorization.

### 3. Minimal Clipping

Avoid `clip: true` unless absolutely required.

### 4. No Blur Effects

Never use `FastBlur`, `GaussianBlur`, etc. Use subtle opacity or darker backgrounds instead.

### 5. Spring Physics Performance

Spring animations are CPU-bound but provide natural motion. Use sparingly:
- ✅ Buttons, cards, modals
- ❌ Large lists, rapid-fire interactions

---

## Migration Guide

### Old vs New Components

| Old | New | Changes |
|-----|-----|---------|
| `Constants.animationFast` | `MMotion.quick` | Spring physics available |
| `MColors.surface` | `MColors.surface1` | Clearer elevation naming |
| Scale animations | Spring animations | Natural motion |
| Static elevation | Dynamic elevation | Responds to interaction |
| Color-only press | Scale + ripple | Richer feedback |

### Example Migration

**Before:**
```qml
Rectangle {
    color: mouseArea.pressed ? "#1A1A1A" : "#0F0F0F"
    
    Behavior on color {
        ColorAnimation { duration: 150 }
    }
}
```

**After:**
```qml
import MarathonUI.Theme
import MarathonUI.Effects

Rectangle {
    color: mouseArea.pressed ? MColors.surface2 : MColors.surface1
    scale: mouseArea.pressed ? 0.98 : 1.0
    
    Behavior on color {
        ColorAnimation { duration: MMotion.quick }
    }
    
    Behavior on scale {
        SpringAnimation { 
            spring: MMotion.springMedium
            damping: MMotion.dampingMedium
        }
    }
    
    MRipple { id: ripple }
    
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        onPressed: function(mouse) {
            ripple.trigger(Qt.point(mouse.x, mouse.y))
            HapticService.light()
        }
    }
}
```

---

## Testing

### Visual Testing

1. ✅ Black background everywhere
2. ✅ Dark grey cards with clear hierarchy (surface1-5)
3. ✅ Teal accent colors pop against dark background
4. ✅ Depth perception through dual-borders
5. ✅ Spring animations feel natural, not robotic
6. ✅ Ripple effects visible on all interactions
7. ✅ Page transitions smooth with parallax

### Performance Testing

```bash
# Run with QML profiler
QML_PROFILER=1 ./marathon-shell

# Monitor FPS
QSG_VISUALIZE=overdraw ./marathon-shell
QSG_VISUALIZE=batches ./marathon-shell
```

### Motion Testing

- Press buttons: Should scale to 0.98 with bounce
- Hover cards: Should lift (elevation increase)
- Page navigation: Should parallax with depth
- State changes: Should animate, not snap

---

## Future Enhancements

1. **Shared element transitions** - Hero animations between pages
2. **Pull-to-refresh** - Spring physics momentum
3. **Rubber-band overscroll** - Bounce at scroll limits
4. **Context menus** - Right-click/long-press menus with choreography
5. **Toast notifications** - Slide-in from bottom with stagger
6. **Dark mode variants** - Lighter theme option
7. **Accessibility** - Screen reader, high contrast, larger targets

---

**Version**: 2.0  
**Last Updated**: October 18, 2025  
**Target**: Raspberry Pi 4 (ARM Cortex-A72)  
**Status**: Production Ready ✅


## Performance Principles

### 1. Opaque Rendering First

**Rule**: All UI elements must use fully opaque colors (alpha = 1.0) unless absolutely necessary.

**Why**: Alpha blending is 2-3x more expensive on embedded GPUs. Every translucent pixel requires reading the background, blending, and writing back.

**Exceptions**:
- Overlay backgrounds: `Qt.rgba(0, 0, 0, 0.8)` - acceptable for modal overlays
- Glass effects (minimal): `Qt.rgba(0.05, 0.05, 0.05, 0.97)` - 97%+ opacity only
- Icon colorization: Icons use `layer.enabled` for SVG tinting (acceptable, small textures)

```qml
// ✅ GOOD - Fully opaque
Rectangle {
    color: "#1A1A1A"  // or MColors.surface
}

// ❌ BAD - Unnecessary alpha
Rectangle {
    color: Qt.rgba(0.1, 0.1, 0.1, 0.95)
}

// ✅ ACCEPTABLE - Modal overlay only
Rectangle {
    color: MColors.overlay  // Qt.rgba(0, 0, 0, 0.8)
}
```

### 2. No layer.enabled (With Exceptions)

**Rule**: Never use `layer.enabled` except for icon colorization.

**Why**: `layer.enabled` creates an offscreen framebuffer object (FBO), which:
- Allocates texture memory (width × height × 4 bytes)
- Requires rendering to texture, then compositing
- Extremely expensive on RPi4 (limited VRAM)

**Only Exception**: `Icon.qml` for SVG colorization
```qml
// ✅ ONLY ACCEPTABLE USE
Image {
    layer.enabled: true
    layer.effect: MultiEffect {
        colorization: 1.0
        colorizationColor: icon.color
    }
}
```

**Alternatives**:
```qml
// ❌ BAD - Creates FBO for shadow
Rectangle {
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
    }
}

// ✅ GOOD - Use dual-border technique instead
Rectangle {
    color: MColors.surface
    border.width: 1
    border.color: MColors.borderOuter
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: "transparent"
        border.width: 1
        border.color: MColors.borderInner
    }
}
```

### 3. Minimal Clipping

**Rule**: Avoid `clip: true` unless absolutely required.

**Why**: Clipping forces the renderer to use stencil buffers, which are expensive on embedded GPUs.

```qml
// ❌ BAD - Unnecessary clip
ListView {
    clip: true  // Not needed if content doesn't overflow
}

// ✅ GOOD - Only clip when necessary
ListView {
    clip: model.count > visibleItems  // Conditional
}
```

### 4. No Blur Effects

**Rule**: Never use blur effects (`FastBlur`, `GaussianBlur`, etc.).

**Why**: Blur requires multiple texture samples per pixel. A 16px blur radius requires ~256 samples per pixel on RPi4.

**Alternative**: Use subtle opacity or darker backgrounds.

```qml
// ❌ BAD - Extremely expensive
Rectangle {
    layer.enabled: true
    layer.effect: FastBlur {
        radius: 32
    }
}

// ✅ GOOD - Subtle opacity
Rectangle {
    color: MColors.glass  // Qt.rgba(0.05, 0.05, 0.05, 0.97)
}
```

## Elevation System

Marathon UI uses a **border-based elevation system** instead of shadows.

### Elevation Levels (0-5)

```qml
import MarathonOS.Shell

Rectangle {
    property int elevation: 2
    
    color: MElevation.getSurface(elevation)  // Lighter surface at higher elevation
    border.width: Constants.borderWidthThin
    border.color: MElevation.getBorderOuter(elevation)
    
    // Inner highlight border
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: "transparent"
        border.width: 1
        border.color: MElevation.getBorderInner(elevation)
    }
}
```

### Elevation Colors

| Level | Surface | Border Outer | Border Inner | Use Case |
|-------|---------|--------------|--------------|----------|
| 0 | `#0A0A0A` | `#000000` | `rgba(1,1,1,0)` | Background |
| 1 | `#0F0F0F` | `#000000` | `rgba(1,1,1,0.03)` | Cards, panels |
| 2 | `#141414` | `#000000` | `rgba(1,1,1,0.05)` | Raised elements |
| 3 | `#1A1A1A` | `#000000` | `rgba(1,1,1,0.08)` | Modals, dialogs |
| 4 | `#1E1E1E` | `#000000` | `rgba(1,1,1,0.10)` | Floating menus |
| 5 | `#222222` | `#000000` | `rgba(1,1,1,0.12)` | Tooltips, popovers |

## Component Library

### MCard

Elevated card container with dual-border depth.

```qml
import MarathonUI.Containers

MCard {
    elevation: 2
    pressed: mouseArea.pressed
    
    content: [
        Text {
            text: "Card content"
            color: MColors.text
        }
    ]
}
```

**Properties**:
- `elevation: int` - Elevation level (0-5)
- `pressed: bool` - Shows pressed state
- `content: alias` - Child items

### MButton

Sharp, BB10-inspired button with inset press state.

```qml
import MarathonUI.Core

MButton {
    text: "Click Me"
    variant: "primary"  // primary, secondary, danger
    size: "medium"  // small, medium, large
    iconName: "check"
    onClicked: console.log("Clicked")
}
```

**Variants**:
- `primary` - Accent color background
- `secondary` - Transparent with border
- `danger` - Error color background

**Press Behavior**: Colors shift (no scale animation - not BB10-like).

### MLayer

Generic elevated container.

```qml
import MarathonUI.Containers

MLayer {
    elevation: 3
    
    content: [
        Column {
            spacing: Constants.spacingMedium
            // Your content here
        }
    ]
}
```

### MInset / MOutset

Border-based depth effects.

```qml
import MarathonUI.Effects

MInset {
    width: 200
    height: 40
    
    content: [
        Text {
            text: "Inset input field"
            anchors.centerIn: parent
        }
    ]
}
```

## Animations

### Performance Mode

```qml
// In Constants.qml
property bool performanceMode: false
readonly property bool enableAnimations: !performanceMode

// In your component
Behavior on color {
    enabled: Constants.enableAnimations
    ColorAnimation { duration: Constants.animationFast }
}
```

**Auto-detection** (future): Detect frame drops and enable performance mode automatically.

### Animation Guidelines

1. **Limit concurrent animations**: Max 2-3 at once
2. **Use ColorAnimation**: Fastest for color changes
3. **Avoid NumberAnimation on size/position**: Triggers layout recalculation
4. **Use SmoothedAnimation**: Better frame pacing than NumberAnimation

```qml
// ✅ GOOD - Color animation
Behavior on color {
    ColorAnimation { duration: 150 }
}

// ❌ BAD - Scale animation triggers layout
Behavior on scale {
    NumberAnimation { duration: 100 }
}

// ✅ GOOD - Opacity animation
Behavior on opacity {
    NumberAnimation { duration: 150 }
}
```

## Memory Management

### No Manual Garbage Collection

```qml
// ❌ BAD - Blocks GUI thread
gc()

// ✅ GOOD - Let Qt handle it automatically
```

### Loader Pattern

```qml
// ✅ GOOD - Explicit control
Loader {
    id: dynamicContent
    active: false  // Load explicitly
    asynchronous: true
    
    onStatusChanged: {
        if (status === Loader.Error) {
            console.error("Failed to load")
        }
    }
}

// To reload:
dynamicContent.active = false
Qt.callLater(() => dynamicContent.active = true)
```

### ListView Optimization

```qml
ListView {
    cacheBuffer: height * 2  // Cache 2 screens worth
    reuseItems: true  // Reuse delegate instances
    clip: model.count > visibleItems  // Only clip if needed
}
```

## Color System

### Surface Colors

```qml
MColors.surface0  // #0A0A0A - Darkest
MColors.surface1  // #0F0F0F
MColors.surface2  // #141414
MColors.surface3  // #1A1A1A
MColors.surface4  // #1E1E1E
MColors.surface5  // #222222 - Lightest
```

### Border Colors

```qml
MColors.borderOuter     // #000000 - Outer shadow
MColors.borderInner     // rgba(1,1,1,0.05) - Inner highlight
MColors.borderHighlight // rgba(1,1,1,0.10) - Brighter highlight
MColors.borderShadow    // rgba(0,0,0,1.0) - Pure black
```

### Glass Effects

```qml
MColors.glass      // rgba(0.05, 0.05, 0.05, 0.97) - Minimal glass
MColors.glassLight // rgba(0.08, 0.08, 0.08, 0.98) - Lighter glass
MColors.glassBorder // rgba(1,1,1,0.12) - Glass border
```

## Border Radii

Marathon UI uses **sharp corners** for BB10 authenticity:

```qml
Constants.borderRadiusSharp  // 2px - Default
Constants.borderRadiusSmall  // 4px - Slightly rounded
Constants.borderRadiusMedium // 8px - Cards
Constants.borderRadiusLarge  // 12px - Modals
```

## Migration Guide

### From components/ui to MarathonUI

| Old Component | New Component | Import |
|---------------|---------------|--------|
| `ui/Button` | `MButton` | `import MarathonUI.Core` |
| `ui/Input` | `MTextInput` | `import MarathonUI.Core` |
| `ui/Modal` | `MModal` | `import MarathonUI.Modals` |
| `ui/ConfirmDialog` | `MConfirmDialog` | `import MarathonUI.Modals` |
| `MarathonCard` | `MCard` | `import MarathonUI.Containers` |

### Example Migration

**Before**:
```qml
import "../components/ui"

Button {
    text: "Click"
    onClicked: console.log("Clicked")
}
```

**After**:
```qml
import MarathonUI.Core

MButton {
    text: "Click"
    variant: "primary"
    size: "medium"
    onClicked: console.log("Clicked")
}
```

## Performance Targets

### Raspberry Pi 4 (4GB RAM)

- **Frame rate**: 60fps (16.67ms per frame)
- **Memory**: <100MB for UI system
- **Startup**: <2s to first frame
- **App launch**: <500ms

### Optimization Checklist

- [ ] All colors fully opaque (except overlays/glass)
- [ ] No `layer.enabled` (except Icon.qml)
- [ ] No blur effects
- [ ] Minimal `clip: true` usage
- [ ] Animations respect `Constants.enableAnimations`
- [ ] ListView uses `cacheBuffer` and `reuseItems`
- [ ] No manual `gc()` calls
- [ ] Borders use plain Rectangle, not effects

## Testing

### Visual Testing

1. Check depth perception with dual-border technique
2. Verify sharp corners (2px radius)
3. Ensure consistent elevation across components
4. Test pressed states (color shift, not scale)

### Performance Testing

```bash
# Run with QML profiler
QML_PROFILER=1 ./marathon-shell

# Monitor FPS
QSG_VISUALIZE=overdraw ./marathon-shell
QSG_VISUALIZE=batches ./marathon-shell
```

### Memory Testing

```bash
# Monitor memory usage
/usr/bin/time -v ./marathon-shell

# Check texture memory
QSG_INFO=1 ./marathon-shell
```

## Future Enhancements

1. **Auto-performance mode**: Detect <30fps and disable animations
2. **Adaptive quality**: Reduce border complexity on slow hardware
3. **Hardware detection**: Auto-tune for RPi3, RPi4, RPi5
4. **Theme variants**: Light mode, high contrast mode
5. **Accessibility**: Screen reader support, larger touch targets

## Resources

- Qt Performance Tips: https://doc.qt.io/qt-6/qtquick-performance.html
- Qt Quick Best Practices: https://doc.qt.io/qt-6/qtquick-bestpractices.html
- Marathon Shell Repo: [Add link]

---

**Version**: 1.0  
**Last Updated**: October 16, 2025  
**Target**: Raspberry Pi 4 (ARM Cortex-A72)

