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
        implicitHeight: qwertyLayout.visible ? qwertyLayout.implicitHeight : symbolLayout.implicitHeight
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
                anchors.margins: 0  // Edge-to-edge
                visible: keyboard.currentLayout === "symbols"
                
                onKeyClicked: function(text) {
                    keyboard.handleKeyPress(text)
                }
                
                onBackspaceClicked: {
                    keyboard.handleBackspace()
                }
                
                onEnterClicked: {
                    keyboard.handleEnter()
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
        }
    }
    
    // Prediction bar - overlays keyboard, doesn't affect height
    Loader {
        id: predictionLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: keyboardLayoutContainer.top
        height: (active && item) ? item.implicitHeight : 0
        active: keyboard.currentWord.length > 0
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
        
        // 3. Update predictions asynchronously (non-blocking)
        updatePredictions()
        
        // Auto-shift logic: shift only applies to next character
        if (keyboard.shifted && !keyboard.capsLock) {
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
            updatePredictions()
        }
        
        keyboard.backspace()
    }
    
    function handleSpace() {
        Logger.info("MarathonKeyboard", "Space pressed")
        
        // If we have a word, check for auto-correction then learn it
        if (keyboard.currentWord.length > 0) {
            var originalWord = keyboard.currentWord
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
            
            keyboard.currentWord = ""
        }
        
        // Auto-capitalize after space (start of new sentence)
        if (!keyboard.capsLock) {
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
        
        // Auto-capitalize after newline
        if (!keyboard.capsLock) {
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
        
        // Use InputContext to replace current word
        inputContextInstance.replaceCurrentWord(word)
        
        // Learn the word
        Dictionary.learnWord(word)
        
        // Clear current word
        keyboard.currentWord = ""
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
        // Get current word from InputContext
        keyboard.currentWord = inputContextInstance.getCurrentWord()
        updatePredictions()
    }
    
    function show() {
        keyboard.active = true
        // Auto-capitalize at start
        keyboard.shifted = true
        Logger.info("MarathonKeyboard", "Keyboard shown")
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

