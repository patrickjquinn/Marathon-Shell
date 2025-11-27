// Marathon Virtual Keyboard - Main Container
// BlackBerry 10-inspired keyboard with Marathon design
// OPTIMIZED FOR ZERO LATENCY INPUT
import QtQuick
import MarathonOS.Shell
import "../UI"
import "../Layouts"
import "../Data"
import "../Input"

Rectangle {
    id: keyboard
    
    // ISSUE D FIX: Domain suggestion engine for URL/email contexts
    DomainSuggestions {
        id: domainSuggestions
    }
    
    // Properties
    property bool active: false
    property string currentLayout: "qwerty"  // qwerty, symbols
    property bool shifted: false
    property bool capsLock: false
    
    // When keyboard becomes active, detect input mode and set correct shift state
    onActiveChanged: {
        if (active) {
            show()  // Call show() to properly initialize shift state
        }
    }
    
    // Reset shift state when switching layouts (unless caps lock is on)
    onCurrentLayoutChanged: {
        if (!capsLock) {
            shifted = false
        }
    }
    
    // Current word being typed (for predictions)
    property string currentWord: ""
    property var currentPredictions: []  // Current word predictions
    
    // ISSUE A FIX: Clear predictions when input is cleared
    onCurrentWordChanged: {
        if (currentWord.length === 0) {
            currentPredictions = []
            Logger.info("MarathonKeyboard", "Input cleared - predictions reset")
        }
    }
    
    // Log predictions when they actually update (not when requested)
    onCurrentPredictionsChanged: {
        if (currentWord.length > 0 && currentPredictions.length > 0) {
            Logger.info("MarathonKeyboard", "Predictions for '" + currentWord + "': " + currentPredictions.join(", "))
        }
    }
    
    // Listen for async predictions from WordEngine
    Connections {
        target: typeof WordEngine !== 'undefined' ? WordEngine : null
        function onPredictionsReady(prefix, predictions) {
            // Only update if this is for our current word
            if (prefix === keyboard.currentWord) {
                keyboard.currentPredictions = predictions
            }
        }
    }
    
    // Double-tap spacebar for period (BB10/iOS feature)
    property real lastSpaceTime: 0
    
    // Double-tap shift for caps lock
    property real lastShiftTime: 0
    
    // Punctuation definitions (Maliit-style)
    readonly property string sentenceEndingPunctuation: "!.?"  // Auto-capitalize after these
    readonly property string wordSeparators: ",.!?:;"  // Word boundaries
    
    // Input context for proper text handling
    property InputContext inputContext: InputContext {
        id: inputContextInstance
        
        onTextInserted: function(text) {
            // Update current word tracking
            if (text === " " || text === "\n") {
                keyboard.currentWord = ""
            }
        }
        
        onBackspacePressed: {
            keyboard.updateCurrentWord()
        }
        
        // Auto-switch keyboard layout based on input type
        onRecommendedLayoutChanged: {
            if (keyboard.active && recommendedLayout !== keyboard.currentLayout) {
                Logger.info("MarathonKeyboard", "Auto-switching layout from '" + keyboard.currentLayout + "' to '" + recommendedLayout + "'")
                keyboard.currentLayout = recommendedLayout
            }
        }
    }
    
    // Signals
    signal keyPressed(string text)
    signal backspace()
    signal enter()
    signal layoutChanged(string layout)
    signal dismissRequested()
    
    // Dimensions
    width: parent ? parent.width : 0
    
    // FIX: Use Column to properly stack prediction bar above keys
    // This ensures the total height is correct and components are positioned within bounds
    implicitHeight: mainColumn.implicitHeight
    height: active ? implicitHeight : 0
    
    // DEBUG: Monitor height changes (disabled for performance)
    // onImplicitHeightChanged: {
    //     Logger.debug("MarathonKeyboard", "implicitHeight changed: " + implicitHeight)
    // }
    
    color: "#1a1a1a"  // Dark grey background for entire keyboard
    border.width: 0
    
    // PERFORMANCE: Enable layer for smooth height animations (keyboard show/hide)
    layer.enabled: true
    layer.smooth: true
    
    Behavior on height {
        NumberAnimation { 
            duration: 100  // Snappier show/hide
            easing.type: Easing.OutCubic  // OutCubic is smoother than OutQuad for UI
        }
    }
    
    // Main column: prediction bar stacked above keyboard keys
    Column {
        id: mainColumn
        anchors.fill: parent
        spacing: 0
        
        // Prediction bar at top
        Loader {
            id: predictionLoader
            width: parent.width
            height: active ? Math.round(40 * Constants.scaleFactor) : 0
            active: keyboard.currentWord.length > 0 && inputContextInstance.shouldShowPredictions
            visible: active
            asynchronous: false
            
            sourceComponent: PredictionBar {
                width: parent.width
                currentWord: keyboard.currentWord
                predictions: keyboard.currentPredictions
                
                onPredictionSelected: function(word) {
                    keyboard.acceptPrediction(word)
                }
            }
            
            Behavior on height {
                NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
            }
        }
        
        // Keyboard layout container below prediction bar
        Item {
            id: keyboardLayoutContainer
            width: parent.width
            height: implicitHeight
            implicitHeight: {
                if (qwertyLayout.visible) return qwertyLayout.implicitHeight
                if (symbolLayout.visible) return symbolLayout.implicitHeight
                if (emailLayout.visible) return emailLayout.implicitHeight
                if (urlLayout.visible) return urlLayout.implicitHeight
                if (numberLayout.visible) return numberLayout.implicitHeight
                if (numberLayout.visible) return numberLayout.implicitHeight
                if (phoneLayout.visible) return phoneLayout.implicitHeight
                if (emojiLayout.visible) return emojiLayout.implicitHeight
                return qwertyLayout.implicitHeight  // Default
            }
            visible: keyboard.active
        
        // QWERTY layout
        QwertyLayout {
            id: qwertyLayout
            anchors.fill: parent
            anchors.margins: 0  // Edge-to-edge
            visible: keyboard.currentLayout === "qwerty"
            shifted: keyboard.shifted
            capsLock: keyboard.capsLock
            
            onKeyClicked: function(text) {
                keyboard.handleKeyPress(text)
            }
            
            onBackspaceClicked: {
                keyboard.handleBackspace()
            }
            
            onEnterClicked: {
                keyboard.handleEnter()
            }
            
            onShiftClicked: {
                keyboard.handleShift()
            }
            
            onSpaceClicked: {
                keyboard.handleSpace()
            }
            
            onLayoutSwitchClicked: function(layout) {
                keyboard.currentLayout = layout
            }
            
            onDismissClicked: {
                keyboard.dismissRequested()
            }
        }
        
        // Symbol layout
        SymbolLayout {
            id: symbolLayout
            anchors.fill: parent
            anchors.margins: 0
            visible: keyboard.currentLayout === "symbols"
            
            onKeyClicked: function(text) { keyboard.handleKeyPress(text) }
            onBackspaceClicked: { keyboard.handleBackspace() }
            onEnterClicked: { keyboard.handleEnter() }
            onSpaceClicked: { keyboard.handleSpace() }
            onLayoutSwitchClicked: function(layout) { keyboard.currentLayout = layout }
            onDismissClicked: { keyboard.dismissRequested() }
        }
        
        // Email layout
        EmailLayout {
            id: emailLayout
            anchors.fill: parent
            anchors.margins: 0
            visible: keyboard.currentLayout === "email"
            
            onKeyClicked: function(text) { keyboard.handleKeyPress(text) }
            onBackspaceClicked: { keyboard.handleBackspace() }
            onEnterClicked: { keyboard.handleEnter() }
            onSpaceClicked: { keyboard.handleSpace() }
            onLayoutSwitchClicked: function(layout) { keyboard.currentLayout = layout }
            onDismissClicked: { keyboard.dismissRequested() }
        }
        
        // URL layout
        UrlLayout {
            id: urlLayout
            anchors.fill: parent
            anchors.margins: 0
            visible: keyboard.currentLayout === "url"
            
            onKeyClicked: function(text) { keyboard.handleKeyPress(text) }
            onBackspaceClicked: { keyboard.handleBackspace() }
            onEnterClicked: { keyboard.handleEnter() }
            onSpaceClicked: { keyboard.handleSpace() }
            onLayoutSwitchClicked: function(layout) { keyboard.currentLayout = layout }
            onDismissClicked: { keyboard.dismissRequested() }
        }
        
        // Number layout
        NumberLayout {
            id: numberLayout
            anchors.fill: parent
            anchors.margins: 0
            visible: keyboard.currentLayout === "number"
            
            onKeyClicked: function(text) { keyboard.handleKeyPress(text) }
            onBackspaceClicked: { keyboard.handleBackspace() }
            onEnterClicked: { keyboard.handleEnter() }
            onSpaceClicked: { keyboard.handleSpace() }
            onLayoutSwitchClicked: function(layout) { keyboard.currentLayout = layout }
            onDismissClicked: { keyboard.dismissRequested() }
        }
        
        // Phone layout
        PhoneLayout {
            id: phoneLayout
            anchors.fill: parent
            anchors.margins: 0
            visible: keyboard.currentLayout === "phone"
            
            onKeyClicked: function(text) { keyboard.handleKeyPress(text) }
            onBackspaceClicked: { keyboard.handleBackspace() }
            onEnterClicked: { keyboard.handleEnter() }
            onSpaceClicked: { keyboard.handleSpace() }
            onLayoutSwitchClicked: function(layout) { keyboard.currentLayout = layout }
            onDismissClicked: { keyboard.dismissRequested() }
        }
        // Emoji layout
        EmojiLayout {
            id: emojiLayout
            anchors.fill: parent
            anchors.margins: 0
            visible: keyboard.currentLayout === "emoji"
            
            onKeyClicked: function(text) { keyboard.handleKeyPress(text) }
            onBackspaceClicked: { keyboard.handleBackspace() }
            onEnterClicked: { keyboard.handleEnter() }
            onSpaceClicked: { keyboard.handleSpace() }
            onLayoutSwitchClicked: function(layout) { keyboard.currentLayout = layout }
            onDismissClicked: { keyboard.dismissRequested() }
        }
    }  // End keyboardLayoutContainer
    }  // End mainColumn
    
    // Functions
    function handleKeyPress(text) {
        // PERFORMANCE: Remove logging from hot path (use debug flag if needed)
        // Logger.debug("MarathonKeyboard", "Key pressed: " + text)
        
        // PERFORMANCE CRITICAL PATH:
        // 1. Update current word immediately (synchronous, < 0.1ms)
        keyboard.currentWord += text
        
        // 2. OPTIMIZED: Commit text immediately (remove artificial 1ms delay)
        // Visual feedback from key press is already instant
        inputContextInstance.insertText(text)
        keyboard.keyPressed(text)
        
        // 3. Update predictions asynchronously (non-blocking) - only if context allows
        if (inputContextInstance.shouldShowPredictions) {
            updatePredictions()
        } else {
            keyboard.currentPredictions = []
        }
        
        // 4. Auto-capitalize after sentence-ending punctuation (Maliit behavior)
        if (keyboard.sentenceEndingPunctuation.indexOf(text) !== -1 && inputContextInstance.shouldAutoCapitalize) {
            if (!keyboard.capsLock) {
                keyboard.shifted = true
                keyboard.currentWord = ""  // Reset word tracking after sentence end
            }
        }
        
        // 5. Auto-space after comma (modern keyboard behavior)
        if (text === ",") {
            commitTimer.pendingText = text + " "  // Add space after comma
            keyboard.currentWord = ""  // Reset word tracking
        }
        
        // Auto-shift logic: shift only applies to next character (and only if auto-cap is enabled)
        if (keyboard.shifted && !keyboard.capsLock && inputContextInstance.shouldAutoCapitalize) {
            keyboard.shifted = false
        }
    }
    
    function handleBackspace() {
        // PERFORMANCE: Remove logging from hot path
        // Logger.debug("MarathonKeyboard", "Backspace pressed")
        
        // Use InputContext for proper backspace
        inputContextInstance.handleBackspace()
        
        // Update current word
        if (keyboard.currentWord.length > 0) {
            keyboard.currentWord = keyboard.currentWord.slice(0, -1)
            
            // If word is now empty, clear predictions immediately
            if (keyboard.currentWord.length === 0) {
                keyboard.currentPredictions = []
            } else {
                updatePredictions()
            }
        }
        
        keyboard.backspace()
    }
    
    function handleSpace() {
        // PERFORMANCE: Remove logging from hot path
        // Logger.debug("MarathonKeyboard", "Space pressed")
        
        var now = Date.now()
        var isDoubleTap = (now - keyboard.lastSpaceTime < 300) && keyboard.currentWord.length === 0
        
        // Double-tap spacebar: replace last space with period + space (BB10/iOS feature)
        if (isDoubleTap && inputContextInstance.shouldAutoCapitalize) {
            // PERFORMANCE: Remove logging from hot path
            // Logger.debug("MarathonKeyboard", "Double-tap spacebar detected - inserting period")
            inputContextInstance.handleBackspace()  // Delete previous space
            inputContextInstance.insertText(". ")
            keyboard.keyPressed(". ")
            keyboard.shifted = true  // Capitalize next letter
            keyboard.lastSpaceTime = 0  // Reset to avoid triple-tap
            return
        }
        
        // If we have a word, check for auto-correction then learn it (only if context allows)
        if (keyboard.currentWord.length > 0) {
            var originalWord = keyboard.currentWord
            
            if (inputContextInstance.shouldAutoCorrect) {
                var correctedWord = AutoCorrect.correct(originalWord)
                
                if (correctedWord !== originalWord) {
                    // Auto-correct was applied
                    // PERFORMANCE: Remove logging from hot path
                    // Logger.debug("MarathonKeyboard", "Auto-corrected: " + originalWord + " -> " + correctedWord)
                    inputContextInstance.replaceCurrentWord(correctedWord)
                    Dictionary.learnWord(correctedWord)
                } else {
                    // No correction, just learn the word
                    Dictionary.learnWord(originalWord)
                }
            }
            
            keyboard.currentWord = ""
        }
        
        // Auto-capitalize after space (start of new sentence) - only if context allows
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize) {
            keyboard.shifted = true
        }
        
        inputContextInstance.insertText(" ")
        keyboard.keyPressed(" ")
        
        // Track space time for double-tap detection
        keyboard.lastSpaceTime = now
    }
    
    function handleEnter() {
        // PERFORMANCE: Remove logging from hot path
        // Logger.debug("MarathonKeyboard", "Enter pressed")
        
        // Learn current word if any
        if (keyboard.currentWord.length > 0) {
            Dictionary.learnWord(keyboard.currentWord)
            keyboard.currentWord = ""
        }
        
        // Auto-capitalize after newline - only if context allows
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize) {
            keyboard.shifted = true
        }
        
        inputContextInstance.handleEnter()
        keyboard.enter()
    }
    
    function handleShift() {
        var now = Date.now()
        var isDoubleTap = (now - keyboard.lastShiftTime < 300)
        
        if (keyboard.capsLock) {
            // If caps lock is on, turn it off
            keyboard.capsLock = false
            keyboard.shifted = false
        } else if (isDoubleTap && keyboard.shifted) {
            // Double-tap while shifted → enable caps lock
            keyboard.capsLock = true
            keyboard.shifted = true
            Logger.info("MarathonKeyboard", "Caps lock enabled (double-tap)")
        } else {
            // Single tap → toggle shift
            keyboard.shifted = !keyboard.shifted
        }
        
        keyboard.lastShiftTime = now
        Logger.info("MarathonKeyboard", "Shift: " + keyboard.shifted + ", Caps: " + keyboard.capsLock)
    }
    
    function acceptPrediction(word) {
        Logger.info("MarathonKeyboard", "Prediction accepted: '" + word + "' (replacing '" + keyboard.currentWord + "')")
        
        // Delete the current word (send backspace for each character)
        var charsToDelete = keyboard.currentWord.length
        Logger.info("MarathonKeyboard", "Deleting " + charsToDelete + " characters")
        for (var i = 0; i < charsToDelete; i++) {
            inputContextInstance.handleBackspace()
        }
        
        // Insert the predicted word WITH trailing space (BB10 behavior)
        inputContextInstance.insertText(word + " ")
        // NOTE: Do NOT emit keyPressed here - that would insert the text twice!
        // inputContextInstance.insertText() already commits the text through the IME
        
        // Learn the word
        Dictionary.learnWord(word)
        
        // Clear current word and predictions
        keyboard.currentWord = ""
        keyboard.currentPredictions = []
        
        // Auto-capitalize after word completion (if context allows)
        if (!keyboard.capsLock && inputContextInstance.shouldAutoCapitalize) {
            keyboard.shifted = true
        }
    }
    
    function updatePredictions() {
        if (keyboard.currentWord.length === 0) {
            keyboard.currentPredictions = []
            return
        }
        
        // ISSUE D FIX: Intelligent context-aware predictions
        var isEmail = inputContextInstance.inputMode === "email"
        var isUrl = inputContextInstance.inputMode === "url"
        
        // For URL/email contexts, prioritize domain suggestions
        if (isEmail || isUrl) {
            if (domainSuggestions.shouldShowDomainSuggestions(keyboard.currentWord, isEmail, isUrl)) {
                var domainSugs = domainSuggestions.getSuggestions(keyboard.currentWord, isEmail)
                if (domainSugs.length > 0) {
                    keyboard.currentPredictions = domainSugs
                    Logger.info("MarathonKeyboard", "Domain suggestions: " + domainSugs.join(", "))
                    return
                }
            }
        }
        
        // Fall back to Hunspell for regular text
        if (inputContextInstance.shouldShowPredictions) {
            keyboard.currentPredictions = Dictionary.predict(keyboard.currentWord)
            // Note: Predictions are logged via onCurrentPredictionsChanged when they actually arrive
        } else {
            keyboard.currentPredictions = []
        }
    }
    
    function updateCurrentWord() {
        // Note: currentWord is tracked internally in handleKeyPress/handleBackspace
        // This function is called when external input events occur (e.g. from InputContext)
        // We just update predictions based on the internally-tracked currentWord
        updatePredictions()
    }
    
    function show() {
        keyboard.active = true
        
        // Detect input mode FIRST before setting shift state
        inputContextInstance.detectInputMode()
        
        // Auto-capitalize at start - only if context allows (e.g. not for URLs/emails)
        if (inputContextInstance.shouldAutoCapitalize) {
            keyboard.shifted = true
        } else {
            keyboard.shifted = false  // Ensure lowercase for URL/email fields
        }
        Logger.info("MarathonKeyboard", "Keyboard shown (shifted: " + keyboard.shifted + ", input mode: " + inputContextInstance.inputMode + ")")
    }
    
    function hide() {
        keyboard.active = false
        keyboard.currentWord = ""
        keyboard.currentPredictions = []
        Logger.info("MarathonKeyboard", "Keyboard hidden")
    }
    
    function clear() {
        keyboard.currentWord = ""
        keyboard.currentPredictions = []
    }
}

