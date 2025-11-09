# Marathon Virtual Keyboard - Technical Specification
**Version:** 1.0  
**Date:** 2025-10-24  
**Status:** PLANNING PHASE - DO NOT IMPLEMENT YET

---

## EXECUTIVE SUMMARY

Replace Qt's InputPanel with a fully custom, BlackBerry 10-inspired virtual keyboard optimized for Marathon OS. This document outlines the research findings, architecture, and implementation plan.

---

## 1. CURRENT STATE ANALYSIS

### 1.1 Qt VirtualKeyboard Integration
**File:** `shell/qml/components/VirtualKeyboard.qml`

**Current Implementation:**
```qml
InputPanel {
    id: inputPanel
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
}
```

**Problems Identified:**
1. **Segfault on dismiss** - Fragile active property binding
2. **No styling control** - InputPanel is opaque Qt component
3. **Generic appearance** - iOS/Android style, not BB10
4. **Limited features** - No word predictions, no flick gestures
5. **No Marathon integration** - Can't use MColors, MMotion, etc.
6. **Performance overhead** - Full Qt VirtualKeyboard stack is heavy

### 1.2 Current Usage Points
- `MarathonShell.qml` line 1117: Main keyboard instance
- `MarathonNavBar.qml`: Toggle button with `keyboard` icon
- Keyboard shortcuts: Cmd+K, Menu key toggle

---

## 2. RESEARCH FINDINGS

### 2.1 Qt VirtualKeyboard Architecture

**Qt VirtualKeyboard Components:**
```
InputPanel (QML)
    ↓
InputContext (C++)
    ↓
InputEngine (C++)
    ↓
AbstractInputMethod (C++ plugin)
```

**Customization Options:**
1. **Styles** - QML style overrides (limited to colors/fonts)
2. **Layouts** - Custom key arrangements (XML-like)
3. **Input Methods** - C++ plugins for predictions (complex)

**Limitations:**
- InputPanel lifecycle is Qt-controlled (hence segfaults)
- Custom input methods require C++ compilation
- Styling is limited to predefined properties
- No access to key press events for gestures
- Hard to integrate with QML-based app architecture

### 2.2 BlackBerry 10 Keyboard Features

**Core BB10 Innovations:**
1. **Flick predictions** - Words appear above keys, flick up to select
2. **Adaptive learning** - Personal dictionary from usage
3. **Swipe gestures**:
   - Swipe left: Delete previous word
   - Swipe right: Accept suggestion
   - Swipe up on space: Select period
4. **Long-press alternates** - Accents and symbols
5. **Smart spacing** - Auto-insert spaces after predictions
6. **Contextual mode** - Email/URL/Phone keyboard variations

**BB10 Layout Characteristics:**
- QWERTY layout with proper key spacing
- 10-key top row (including numbers)
- Dedicated punctuation keys
- Prediction bar above keyboard (3 suggestions)
- Backspace with repeat on long-press
- Space bar spanning 4 keys width

---

## 3. PROPOSED ARCHITECTURE

### 3.1 Component Structure

```
MarathonKeyboard/
├── Core/
│   ├── MarathonKeyboard.qml         # Main container & orchestrator
│   ├── KeyboardEngine.qml            # Input processing & prediction logic
│   └── KeyboardState.qml             # State management singleton
│
├── UI/
│   ├── KeyboardLayout.qml            # Key grid renderer
│   ├── Key.qml                       # Individual key component
│   ├── PredictionBar.qml             # Word suggestions (top bar)
│   └── LayoutIndicator.qml           # ABC/123/!@# indicator
│
├── Layouts/
│   ├── LayoutBase.qml                # Base layout type
│   ├── QwertyLayout.qml              # Standard QWERTY
│   ├── SymbolLayout.qml              # !@#$%^&*()
│   └── NumberLayout.qml              # 123 + operators
│
├── Input/
│   ├── InputHandler.qml              # Key press routing
│   ├── GestureDetector.qml           # Swipe/flick detection
│   └── LongPressHandler.qml          # Accent/alt detection
│
└── Data/
    ├── Dictionary.qml                # Word list & frequency
    ├── PredictionEngine.qml          # Next-word algorithm
    └── UserDictionary.qml            # Learned words storage
```

### 3.2 Data Flow

```
User Touch Event
    ↓
GestureDetector (detect tap/swipe/flick/longpress)
    ↓
InputHandler (route to appropriate handler)
    ↓
    ├─ Tap → Key press → KeyboardEngine
    ├─ Swipe → Gesture action (delete word, etc.)
    ├─ Flick → Prediction selection
    └─ LongPress → Show alternates popup
    ↓
KeyboardEngine (process input)
    ↓
    ├─ Update text buffer
    ├─ Query Dictionary for predictions
    ├─ Update PredictionBar
    └─ Emit text to focused TextInput
```

### 3.3 Integration Points

**Inputs:**
- Focus events from Qt.inputMethod
- Text input from Key components
- Gesture events from GestureDetector

**Outputs:**
- `commit(text)` → Send to focused TextInput
- `preedit(text)` → Show uncommitted text (predictions)
- `backspace()` → Delete character
- `clear()` → Clear all text

---

## 4. TECHNICAL DECISIONS

### 4.1 Pure QML vs C++ Plugin

**Decision: START with Pure QML**

**Rationale:**
- Faster iteration and debugging
- Full access to Marathon design system (MColors, MMotion)
- No compilation step for changes
- Easier to maintain
- Can add C++ optimization layer later if needed

**Trade-offs:**
- Predictions will be simpler initially (no ML)
- Dictionary lookups might be slower (acceptable for embedded)
- Can't use Qt's built-in input method framework

### 4.2 Dictionary Implementation

**Option A: JSON file** (CHOSEN)
```json
{
  "words": [
    {"word": "the", "frequency": 10000},
    {"word": "be", "frequency": 8500},
    ...
  ]
}
```

**Option B: SQLite database**
- Overkill for initial version
- Adds dependency
- Save for v2 if performance needed

**Option C: Trie data structure in JS**
- Best for lookups
- Implement in QML/JS
- Load common 10k words on startup

### 4.3 Prediction Algorithm

**Phase 1: Simple Prefix Matching**
```javascript
function predict(prefix) {
    return dictionary
        .filter(w => w.startsWith(prefix))
        .sort((a,b) => b.frequency - a.frequency)
        .slice(0, 3)
}
```

**Phase 2: N-gram Context** (Future)
- Track word pairs/triplets
- "I am" → predict "going", "happy", "sorry"
- Requires user data collection

### 4.4 Performance Targets

**Metrics:**
- Key press latency: < 16ms (60fps)
- Prediction update: < 50ms
- Dictionary load: < 500ms on startup
- Memory footprint: < 10MB for dictionary

---

## 5. IMPLEMENTATION PLAN

### Phase 1: Foundation (Week 1)
- [ ] Create directory structure
- [ ] Implement Key.qml with Marathon styling
- [ ] Implement KeyboardLayout.qml with QWERTY grid
- [ ] Basic key press → text output
- [ ] Replace InputPanel in VirtualKeyboard.qml

### Phase 2: Core Features (Week 2)
- [ ] PredictionBar component
- [ ] Simple prefix-based dictionary (1k words)
- [ ] Tap prediction to insert
- [ ] Backspace with character delete
- [ ] Space bar behavior

### Phase 3: BB10 Features (Week 3)
- [ ] Flick gesture on predictions
- [ ] Long-press for alternates (à, é, ñ)
- [ ] Swipe-left to delete word
- [ ] Symbol/number layout switching
- [ ] Shift key behavior

### Phase 4: Polish (Week 4)
- [ ] Haptic feedback integration
- [ ] Spring physics animations
- [ ] Auto-capitalization
- [ ] Auto-spacing after predictions
- [ ] User dictionary learning

---

## 6. RISKS & MITIGATIONS

### Risk 1: Qt Input Method Integration
**Problem:** Custom keyboard might not work with all Qt text fields

**Mitigation:**
- Test with TextInput, TextField, TextArea
- Use Qt.inputMethod.commit() for compatibility
- Fallback to direct text property assignment

### Risk 2: Performance on Embedded
**Problem:** Dictionary lookups might be slow on RPi4

**Mitigation:**
- Limit dictionary to 10k most common words
- Use Trie structure for O(k) lookups
- Lazy-load extended dictionary
- Profile with QML Profiler

### Risk 3: Gesture Conflicts
**Problem:** Swipe gestures might conflict with scrolling

**Mitigation:**
- Only detect gestures within keyboard bounds
- Require minimum swipe distance (50px)
- Use velocity threshold for flick detection

### Risk 4: Maintenance Burden
**Problem:** Custom keyboard is complex to maintain

**Mitigation:**
- Comprehensive unit tests (when possible in QML)
- Documentation of all gesture behaviors
- Modular architecture for easy updates

---

## 7. SUCCESS CRITERIA

### Must Have:
 Faster typing than Qt InputPanel  
 Word predictions with 70%+ accuracy  
 Flick gestures working smoothly  
 Marathon design system integration  
 No crashes or segfaults  
 Works with all Marathon apps  

### Nice to Have:
- Auto-correction
- Personal dictionary learning
- Gesture typing (swype)
- One-handed mode
- Theme switching

---

## 8. NEXT STEPS

### Before Implementation:
1. **Review this spec** - Get feedback on architecture
2. **Test Qt.inputMethod** - Verify text input APIs work
3. **Prototype Key component** - Test Marathon styling
4. **Research Trie implementation** - Best data structure for dictionary
5. **Find word frequency list** - Need top 10k English words with frequencies

### First Code:
- Start with Key.qml
- Test single key press → text output
- Verify Marathon design system integration

---

## APPROVAL REQUIRED

This specification must be reviewed and approved before implementation begins.

**Approver:** User  
**Date:** _____________  
**Status:** ⏳ PENDING REVIEW

