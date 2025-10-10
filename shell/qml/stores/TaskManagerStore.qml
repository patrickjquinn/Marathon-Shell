pragma Singleton
import QtQuick

QtObject {
    id: taskManager
    
    property var runningTasks: []
    property var recentTasks: []
    property int maxRecentTasks: 8
    
    // Current active task
    property var activeTask: null
    
    // Task model
    Component.onCompleted: {
        // Initialize with some mock tasks
        runningTasks = [
            {
                id: "task_1",
                appId: "browser",
                title: "Browser",
                icon: "qrc:/images/browser.svg",
                color: "#4A90E2",
                preview: null,
                timestamp: Date.now()
            },
            {
                id: "task_2",
                appId: "messages",
                title: "Messages",
                icon: "qrc:/images/messages.svg",
                color: "#7ED321",
                preview: null,
                timestamp: Date.now() - 10000
            },
            {
                id: "task_3",
                appId: "calendar",
                title: "Calendar",
                icon: "qrc:/images/calendar.svg",
                color: "#F5A623",
                preview: null,
                timestamp: Date.now() - 20000
            }
        ]
        activeTask = runningTasks[0]
    }
    
    function launchTask(appId, appName, appIcon) {
        var existingTask = runningTasks.find(t => t.appId === appId)
        
        if (existingTask) {
            // Switch to existing task
            activeTask = existingTask
            return existingTask
        }
        
        // Create new task
        var task = {
            id: "task_" + Date.now(),
            appId: appId,
            title: appName,
            icon: appIcon,
            color: getRandomColor(),
            preview: null,
            timestamp: Date.now()
        }
        
        runningTasks.push(task)
        runningTasks = runningTasks // Trigger property change
        activeTask = task
        
        // Add to recent tasks
        addToRecent(task)
        
        console.log("Task launched:", appName)
        return task
    }
    
    function closeTask(taskId) {
        runningTasks = runningTasks.filter(t => t.id !== taskId)
        
        if (activeTask && activeTask.id === taskId) {
            activeTask = runningTasks.length > 0 ? runningTasks[runningTasks.length - 1] : null
        }
        
        console.log("Task closed:", taskId)
    }
    
    function switchToTask(taskId) {
        var task = runningTasks.find(t => t.id === taskId)
        if (task) {
            activeTask = task
            console.log("Switched to task:", task.title)
        }
    }
    
    function addToRecent(task) {
        // Remove if already in recent
        recentTasks = recentTasks.filter(t => t.id !== task.id)
        
        // Add to front
        recentTasks.unshift(task)
        
        // Trim to max
        if (recentTasks.length > maxRecentTasks) {
            recentTasks = recentTasks.slice(0, maxRecentTasks)
        }
    }
    
    function getRandomColor() {
        var colors = ["#4A90E2", "#7ED321", "#F5A623", "#D0021B", "#9013FE", "#50E3C2", "#F8E71C"]
        return colors[Math.floor(Math.random() * colors.length)]
    }
    
    function closeAllTasks() {
        runningTasks = []
        activeTask = null
    }
}

