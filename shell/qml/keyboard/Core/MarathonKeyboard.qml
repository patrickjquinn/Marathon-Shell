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
    
    // Properties
    property bool active: false
    property string currentLayout: "qwerty"  // qwerty, symbols
    property bool shifted: false
    property bool capsLock: false
    
    // Current word being typed (for predictions)
    property string currentWord: ""
    property var currentPredictions: []  // Current word predictions
    
    // PERFORMANCE: Timer for async text commit
    // This allows visual feedback to show BEFORE text is committed
    property Timer textCommitTimer: Timer {
        id: commitTimer
        interval: 1 // 1ms delay - imperceptible but allows frame to render
        repeat: false
        property string pendingText: ""
        onTriggered: {
            if (pendingText !== "") {
                inputContextInstance.insertText(pendingText)
                keyboard.keyPressed(pendingText)
                pendingText = ""
            }
        }
    }
    
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
    
    // Let keyboard layout determine height (prediction bar overlays, doesn't affect height)
    implicitHeight: keyboardLayoutContainer.implicitHeight
    height: active ? implicitHeight : 0
    
    color: "#1a1a1a"  // Dark grey background for entire keyboard
    border.width: 0
    
    Behavior on height {
        NumberAnimation { 
            duration: 120
            easing.type: Easing.OutQuad
        }
    }
    
    // Keyboard layout container (determines keyboard height)
    Item {
        id: keyboardLayoutContainer
        width: parent.width
        implicitHeight: {
            if (qwertyLayout.visible) return qwertyLayout.implicitHeight
            if (symbolLayout.visible) return symbolLayout.implicitHeight
            if (emailLayout.visible) return emailLayout.implicitHeight
            if (urlLayout.visible) return urlLayout.implicitHeight
            if (numberLayout.visible) return numberLayout.implicitHeight
            if (phoneLayout.visible) return phoneLayout.implicitHeight
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
            
            // Word Fling (BB10 feature)
            currentWord: keyboard.currentWord
            predictions: keyboard.currentPredictions
            
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
            
            onWordFlung: function(word) {
                keyboard.acceptPrediction(word)
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
    }
    
    // Prediction bar - overlays keyboard, doesn't affect height
    Loader {
        id: predictionLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: keyboardLayoutContainer.top
        height: (active && item) ? item.implicitHeight : 0
        active: keyboard.currentWord.length > 0 && inputContextInstance.shouldShowPredictions
        visible: active
        z: 100
        
        sourceComponent: PredictionBar {
            width: parent.width
            currentWord: keyboard.currentWord
            predictions: keyboard.currentPredictions
            
            onPredictionSelected: function(word) {
                keyboard.acceptPrediction(word)
            }
        }
        
        // Smooth height transition
        Behavior on height {
            NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
        }
    }
    
    // Functions
    function handleKeyPress(text) {
        Logger.info("MarathonKeyboard", "Key pressed: " + text)
        
        // PERFORMANCE CRITICAL PATH:
        // 1. Update current word immediately (synchronous, < 0.1ms)
        keyboard.currentWord += text
        
        // 2. Schedule async text commit (visual feedback shows first)
        commitTimer.pendingText = text
        commitTimer.restart()
        
        // 3. Update predictions asynchronously (non-blocking) - only if context allows
        if (inputContextInstance.shouldShowPredictions) {
            updatePredictions()
        } else {
            keyboard.currentPredictions = []
        }
        
        // Auto-shift logic: shift only applies to next character (and only if auto-cap is enabled)
        if (keyboard.shifted && !keyboard.capsLock && inputContextInstance.shouldAutoCapitalize) {
            keyboard.shifted = false
        }
    }
    
    function handleBackspace() {
        Logger.info("MarathonKeyboard", "Backspace pressed")
        
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
        Logger.info("MarathonKeyboard", "Space pressed")
        
        // If we have a word, check for auto-correction then learn it (only if context allows)
        if (keyboard.currentWord.length > 0) {
            var originalWord = keyboard.currentWord
            
            if (inputContextInstance.shouldAutoCorrect) {
                var correctedWord = AutoCorrect.correct(originalWord)
                
                if (correctedWord !== originalWord) {
                    // Auto-correct was applied
                    Logger.info("MarathonKeyboard", "Auto-corrected: " + originalWord + " -> " + correctedWord)
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
    }
    
    function handleEnter() {
        Logger.info("MarathonKeyboard", "Enter pressed")
        
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
        if (keyboard.capsLock) {
            keyboard.capsLock = false
            keyboard.shifted = false
        } else if (keyboard.shifted) {
            keyboard.capsLock = true
        } else {
            keyboard.shifted = true
        }
        
        Logger.info("MarathonKeyboard", "Shift: " + keyboard.shifted + ", Caps: " + keyboard.capsLock)
    }
    
    function acceptPrediction(word) {
        Logger.info("MarathonKeyboard", "Prediction accepted: " + word)
        
        // Delete the current word (send backspace for each character)
        var charsToDelete = keyboard.currentWord.length
        for (var i = 0; i < charsToDelete; i++) {
            inputContextInstance.handleBackspace()
        }
        
        // Insert the predicted word
        inputContextInstance.insertText(word)
        keyboard.keyPressed(word)
        
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
        if (keyboard.currentWord.length > 0) {
            keyboard.currentPredictions = Dictionary.predict(keyboard.currentWord)
            Logger.info("MarathonKeyboard", "Predictions for '" + keyboard.currentWord + "': " + keyboard.currentPredictions.join(", "))
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

