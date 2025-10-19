pragma Singleton
import QtQuick

QtObject {
    id: motion
    
    // =========================================================================
    // DURATION TOKENS (iOS-inspired, performance-tuned)
    // =========================================================================
    
    readonly property int instant: 0
    readonly property int micro: 100      // Micro-interactions (hover, ripple start)
    readonly property int quick: 200      // Button press, toggle, chip select
    readonly property int moderate: 300   // Card animations, sheet slide
    readonly property int slow: 400       // Modal fade, page transitions
    readonly property int slower: 600     // Complex choreography
    
    // Legacy aliases for backward compatibility
    readonly property int animationFast: quick
    readonly property int animationNormal: moderate
    readonly property int animationSlow: slow
    
    // =========================================================================
    // SPRING PHYSICS (Natural motion)
    // =========================================================================
    
    // Spring stiffness (higher = faster oscillation)
    readonly property real springLight: 1.5      // Bouncy, playful (cards, buttons)
    readonly property real springMedium: 2.0     // Balanced (sheets, modals)
    readonly property real springHeavy: 3.0      // Firm, precise (toggles, sliders)
    
    // Damping ratio (higher = less overshoot)
    readonly property real dampingLight: 0.15    // Visible bounce (fun interactions)
    readonly property real dampingMedium: 0.25   // Slight overshoot (natural feel)
    readonly property real dampingHeavy: 0.4     // Controlled, minimal overshoot
    readonly property real dampingCritical: 0.5  // No overshoot (precise controls)
    
    // Spring precision
    readonly property real epsilon: 0.01
    
    // =========================================================================
    // EASING CURVES (BB10 + Material Design inspired)
    // =========================================================================
    
    readonly property int easingStandard: Easing.OutCubic      // Default, smooth deceleration
    readonly property int easingDecelerate: Easing.OutQuint    // Heavy deceleration (entering elements)
    readonly property int easingAccelerate: Easing.InQuint     // Heavy acceleration (exiting elements)
    readonly property int easingEmphasized: Easing.OutExpo     // Dramatic emphasis (important actions)
    readonly property int easingSharp: Easing.InOutQuad        // Sharp, precise (BB10-like)
    readonly property int easingLinear: Easing.Linear          // Constant speed (rotations, progress)
    
    // Legacy alias
    readonly property int easingBB10: easingSharp
    
    // =========================================================================
    // CHOREOGRAPHY (Staggered animations)
    // =========================================================================
    
    readonly property int staggerMicro: 20      // Tight sequence (list items)
    readonly property int staggerShort: 50      // Standard sequence (card grid)
    readonly property int staggerMedium: 80     // Relaxed sequence (large lists)
    readonly property int staggerLong: 120      // Dramatic reveal (hero elements)
    
    // =========================================================================
    // GESTURE PHYSICS
    // =========================================================================
    
    readonly property real flickVelocityMultiplier: 1.5
    readonly property real rubberBandResistance: 0.3    // How much resistance at bounds (0-1)
    readonly property real snapThreshold: 0.5           // Snap point threshold (0-1)
    
    // =========================================================================
    // ELEVATION TRANSITIONS (How fast elevation changes)
    // =========================================================================
    
    readonly property int elevationRaise: quick         // Lift on press
    readonly property int elevationLower: moderate      // Return to rest
    
    // =========================================================================
    // RIPPLE EFFECT
    // =========================================================================
    
    readonly property int rippleDuration: slow          // Total ripple animation
    readonly property real rippleMaxRadius: 2.5         // Max size multiplier
    readonly property real rippleOpacity: 0.12          // Ripple visibility (subtle)
    
    // =========================================================================
    // STATE TRANSITIONS
    // =========================================================================
    
    readonly property int stateChange: quick            // Button states, toggle
    readonly property int loadingAppear: moderate       // Spinner fade-in
    readonly property int successFlash: 400             // Success checkmark
    readonly property int errorShake: 300               // Error shake duration
    
    // =========================================================================
    // PAGE TRANSITIONS
    // =========================================================================
    
    readonly property int pageSlide: moderate           // Page enter/exit
    readonly property real pageParallaxOffset: 0.3       // Background page offset (0-1)
    readonly property real pageScaleOut: 0.92           // Background page scale
    
    // =========================================================================
    // HELPER FUNCTIONS
    // =========================================================================
    
    // Get stagger delay for index
    function staggerDelay(index, stagger) {
        return index * (stagger || staggerShort)
    }
    
    // Interpolate between two values
    function lerp(a, b, t) {
        return a + (b - a) * Math.max(0, Math.min(1, t))
    }
    
    // Smooth step interpolation (ease in and out)
    function smoothstep(t) {
        t = Math.max(0, Math.min(1, t))
        return t * t * (3 - 2 * t)
    }
}

