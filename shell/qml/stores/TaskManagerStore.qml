pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: taskManager
    
    property var runningTasks: []
    property var recentTasks: []
    property int maxRecentTasks: 8
    property int taskCount: 0
    
    // Current active task
    property var activeTask: null
    
    // Task model
    
    function launchTask(appId, appName, appIcon, appType, surfaceId) {
        var existingTask = runningTasks.find(t => t.appId === appId)
        
        if (existingTask) {
            existingTask.state = "active"
            if (activeTask && activeTask.id !== existingTask.id) {
                activeTask.state = "background"
            }
            activeTask = existingTask
            runningTasks = runningTasks
            return existingTask
        }
        
        var task = {
            id: "task_" + Date.now(),
            appId: appId,
            title: appName,
            subtitle: getSubtitleForApp(appId),
            icon: appIcon,
            color: getRandomColor(),
            preview: null,
            timestamp: Date.now(),
            state: "active",
            type: appType || "marathon",
            surfaceId: surfaceId || -1
        }
        
        if (activeTask) {
            activeTask.state = "background"
        }
        
        runningTasks.push(task)
        var newArray = runningTasks.slice()
        runningTasks = newArray
        taskCount = runningTasks.length
        activeTask = task
        
        addToRecent(task)
        
        return task
    }
    
    function closeTask(taskId) {
        runningTasks = runningTasks.filter(t => t.id !== taskId)
        
        if (activeTask && activeTask.id === taskId) {
            activeTask = runningTasks.length > 0 ? runningTasks[runningTasks.length - 1] : null
        }
        
        Logger.info("TaskManager", "Closed: " + taskId)
    }
    
    function switchToTask(taskId) {
        var task = runningTasks.find(t => t.id === taskId)
        if (task) {
            activeTask = task
            Logger.info("TaskManager", "Switched to: " + task.title)
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
    
    function getSubtitleForApp(appId) {
        var subtitles = {
            "browser": "3 tabs open",
            "messages": "2 new messages",
            "email": "5 unread emails",
            "calendar": "Next: Meeting at 3 PM",
            "phone": "Recent: Mom",
            "camera": "12 photos",
            "gallery": "248 photos",
            "music": "Playing: My Playlist",
            "clock": "2 alarms set",
            "notes": "5 notes",
            "calculator": "Ready",
            "maps": "Saved: Home",
            "settings": "Configuring"
        }
        return subtitles[appId] || "Running"
    }
    
    function closeAllTasks() {
        runningTasks = []
        activeTask = null
    }
}

