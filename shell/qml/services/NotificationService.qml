pragma Singleton
import QtQuick

/**
 * @singleton
 * @brief Manages system-wide notifications
 *
 * NotificationService provides a centralized system for sending, managing,
 * and tracking notifications. Integrates with platform notification systems
 * (D-Bus on Linux, NSUserNotification on macOS).
 *
 * @example
 * // Send a simple notification
 * NotificationService.sendNotification(
 *     "myapp",
 *     "Hello World",
 *     "This is a notification body"
 * )
 *
 * @example
 * // Send notification with actions
 * NotificationService.sendNotification(
 *     "messages",
 *     "New Message",
 *     "John: Hey, are you free?",
 *     {
 *         icon: "qrc:/images/messages.svg",
 *         category: "message",
 *         priority: "high",
 *         actions: ["reply", "dismiss"]
 *     }
 * )
 */
QtObject {
    id: notificationService

    /**
     * @brief Array of all notifications
     * @type {Array<Object>}
     */
    property var notifications: []

    /**
     * @brief Count of unread notifications
     * @type {int}
     */
    property int unreadCount: 0

    /**
     * @brief Whether notifications are globally enabled
     * @type {bool}
     * @default true
     */
    property bool notificationsEnabled: true

    /**
     * @brief Whether notification sounds are enabled
     * @type {bool}
     * @default true
     */
    property bool soundEnabled: true

    /**
     * @brief Whether notification vibrations are enabled
     * @type {bool}
     * @default true
     */
    property bool vibrationEnabled: true

    property bool ledEnabled: true

    /**
     * @brief Whether Do Not Disturb mode is active
     * @type {bool}
     * @default false
     */
    property bool isDndEnabled: false

    /**
     * @brief Track last notification ID per app for replacement
     * @type {Object} Map of appId -> notification ID
     * @private
     */
    property var appNotificationIds: ({})

    /**
     * @brief Emitted when a new notification is received
     * @param {Object} notification - The notification object
     */
    signal notificationReceived(var notification)

    /**
     * @brief Emitted when a notification is dismissed
     * @param {int} id - Notification ID
     */
    signal notificationDismissed(int id)

    /**
     * @brief Emitted when a notification is clicked
     * @param {int} id - Notification ID
     */
    signal notificationClicked(int id)

    /**
     * @brief Emitted when a notification action button is triggered
     * @param {int} id - Notification ID
     * @param {string} action - Action identifier
     */
    signal notificationActionTriggered(int id, string action)

    /**
     * @brief Sends a new notification
     *
     * @param {string} appId - Application identifier
     * @param {string} title - Notification title
     * @param {string} body - Notification body text
     * @param {Object} options - Optional configuration
     * @param {string} options.icon - Icon URL
     * @param {string} options.image - Large image URL
     * @param {string} options.category - Category ("message", "email", "system", etc.)
     * @param {string} options.priority - Priority level ("low", "normal", "high")
     * @param {Array<string>} options.actions - Action button labels
     * @param {bool} options.persistent - Whether notification persists until dismissed
     *
     * @returns {int} Notification ID, or -1 if notifications disabled
     *
     * @example
     * const id = NotificationService.sendNotification(
     *     "calendar",
     *     "Meeting in 5 minutes",
     *     "Team standup in Conference Room A",
     *     {
     *         icon: "qrc:/images/calendar.svg",
     *         category: "reminder",
     *         priority: "high",
     *         persistent: true
     *     }
     * )
     */
    function sendNotification(appId, title, body, options) {
        if (!notificationsEnabled) {
            console.log("[NotificationService] Notifications disabled, ignoring");
            return -1;
        }

        // Following freedesktop.org spec: ALL apps (internal or external) call the DBus interface
        // The notification daemon (shell) handles everything in _handleExternalNotification()
        // This prevents duplicate handling and follows the standard architecture

        console.log("[NotificationService] Sending notification via DBus:", title);

        // Build notification object for DBus call
        var notification = {
            appId: appId || "system",
            title: title || "",
            body: body || "",
            icon: options?.icon || "",
            category: options?.category || "message",
            priority: options?.priority || "normal",
            actions: options?.actions || [],
            persistent: options?.persistent || false
        };

        // Call DBus interface - this will trigger _handleExternalNotification() which does:
        // - Add to NotificationModel
        // - Add to internal notifications array
        // - Play sound/haptic
        // - Show UI
        _platformNotify(notification);

        // Return -1 for now (we'll get the real ID from the DBus callback)
        return -1;
    }

    function dismissNotification(id) {
        console.log("[NotificationService] Dismissing notification:", id);

        var found = false;
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].id === id) {
                found = true;
                var appId = notifications[i].appId;

                if (!notifications[i].read) {
                    unreadCount = Math.max(0, unreadCount - 1);
                }
                notifications.splice(i, 1);
                notificationDismissed(id);

                // Clear the tracked ID for this app
                if (appNotificationIds[appId] === id) {
                    delete appNotificationIds[appId];
                }
                break;
            }
        }

        // CRITICAL: Always dismiss from NotificationModel and DBus, even if not in internal array
        // This handles race conditions where notification hasn't been fully processed yet
        if (!found) {
            console.warn("[NotificationService] Notification", id, "not found in internal array (possible race condition)");
        }
        NotificationModel.dismissNotification(id);
        _platformDismissNotification(id);
    }

    function dismissAllNotifications() {
        console.log("[NotificationService] Dismissing all notifications");
        notifications = [];
        unreadCount = 0;
        _platformDismissAllNotifications();
        NotificationModel.dismissAllNotifications();
    }

    function markAsRead(id) {
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].id === id && !notifications[i].read) {
                notifications[i].read = true;
                unreadCount = Math.max(0, unreadCount - 1);
                NotificationModel.markAsRead(id);
                break;
            }
        }
    }

    function markAllAsRead() {
        console.log("[NotificationService] Marking all as read");
        for (var i = 0; i < notifications.length; i++) {
            if (!notifications[i].read) {
                notifications[i].read = true;
                NotificationModel.markAsRead(notifications[i].id);
            }
        }
        unreadCount = 0;
    }

    function clearAll() {
        console.log("[NotificationService] Clearing all notifications");
        var notifIds = notifications.map(function (n) {
            return n.id;
        });
        for (var i = 0; i < notifIds.length; i++) {
            dismissNotification(notifIds[i]);
        }
    }

    function clickNotification(id) {
        console.log("[NotificationService] Notification clicked:", id);
        markAsRead(id);
        notificationClicked(id);
        _platformNotificationClicked(id);
    }

    function triggerAction(id, action) {
        console.log("[NotificationService] Action triggered:", id, action);
        notificationActionTriggered(id, action);
        _platformNotificationAction(id, action);
    }

    function getNotification(id) {
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].id === id) {
                return notifications[i];
            }
        }
        return null;
    }

    function getNotificationsByApp(appId) {
        return notifications.filter(function (n) {
            return n.appId === appId;
        });
    }

    function getUnreadNotifications() {
        return notifications.filter(function (n) {
            return !n.read;
        });
    }

    function getNotificationCountForApp(appId) {
        var count = 0;
        for (var i = 0; i < notifications.length; i++) {
            if (notifications[i].appId === appId && !notifications[i].read) {
                count++;
            }
        }
        return count;
    }

    function _platformNotify(notification) {
        if (Platform.isLinux) {
            // Emit via org.freedesktop.Notifications DBus interface
            if (typeof FreedesktopNotifications !== 'undefined') {
                console.log("[NotificationService] Emitting D-Bus notification:", notification.title);

                // Convert actions array to QStringList format (key, label, key, label, ...)
                var actionsList = [];
                if (notification.actions && notification.actions.length > 0) {
                    for (var i = 0; i < notification.actions.length; i++) {
                        actionsList.push(notification.actions[i]);  // key
                        actionsList.push(notification.actions[i]);  // label (same as key for simplicity)
                    }
                }

                // Build hints map
                var hints = {
                    "category": notification.category,
                    "urgency": notification.priority === "high" ? 2 : (notification.priority === "low" ? 0 : 1),
                    "desktop-entry": notification.appId
                };

                // Get the last notification ID for this app (for replacement)
                // Per freedesktop spec: if replaces_id > 0, the new notification replaces the old one
                var replacesId = appNotificationIds[notification.appId] || 0;

                // Call the C++ DBus service
                var newId = FreedesktopNotifications.Notify(notification.appId           // app_name
                , replacesId                   // replaces_id (0 = new, >0 = replace existing)
                , notification.icon || ""      // app_icon
                , notification.title           // summary
                , notification.body            // body
                , actionsList                  // actions
                , hints                        // hints
                , notification.persistent ? 0 : 5000  // expire_timeout (0 = never, else milliseconds)
                );

                // Store the new ID for future replacements
                appNotificationIds[notification.appId] = newId;
            } else {
                console.warn("[NotificationService] FreedesktopNotifications not available");
            }
        } else if (Platform.isMacOS) {
            console.log("[NotificationService] macOS NSUserNotification");
        }
    }

    function _platformDismissNotification(id) {
        console.log("[NotificationService] _platformDismissNotification called for id:", id);
        console.log("[NotificationService] Platform.isLinux:", Platform.isLinux);
        console.log("[NotificationService] FreedesktopNotifications available:", typeof FreedesktopNotifications);

        if (Platform.isLinux) {
            if (typeof FreedesktopNotifications !== 'undefined' && FreedesktopNotifications !== null) {
                console.log("[NotificationService] D-Bus CloseNotification:", id);
                try {
                    FreedesktopNotifications.CloseNotification(id);
                    console.log("[NotificationService] CloseNotification call completed");
                } catch (error) {
                    console.error("[NotificationService] Error calling CloseNotification:", error);
                }
            } else {
                console.warn("[NotificationService] FreedesktopNotifications not available for CloseNotification");
            }
        } else {
            console.log("[NotificationService] Not on Linux, skipping CloseNotification");
        }
    }

    function _platformDismissAllNotifications() {
        if (Platform.isLinux) {
            console.log("[NotificationService] Dismissing all via D-Bus");
        }
    }

    function _platformNotificationClicked(id) {
        if (Platform.isLinux) {
            console.log("[NotificationService] D-Bus NotificationClosed with reason 2 (clicked)");
        }
    }

    function _platformNotificationAction(id, action) {
        if (Platform.isLinux) {
            console.log("[NotificationService] D-Bus ActionInvoked:", id, action);
        }
    }

    function _populateTestNotifications() {
        sendNotification("messages", "John Doe", "Hey, are you free tonight?", {
            icon: "qrc:/images/messages.svg",
            category: "message",
            priority: "high",
            actions: ["reply", "dismiss"]
        });

        sendNotification("email", "Work Email", "Meeting moved to 3pm", {
            icon: "qrc:/images/calendar.svg",
            category: "email",
            priority: "normal"
        });

        sendNotification("system", "System Update", "Software update available", {
            icon: "qrc:/images/settings.svg",
            category: "system",
            priority: "low"
        });
    }

    // Handler for ALL notifications coming via DBus (FreedesktopNotifications)
    // Following freedesktop.org spec: This is the SINGLE point where all notifications are processed
    // Both internal Marathon OS apps and external apps go through this path
    function _handleExternalNotification(id) {
        console.log("[NotificationService] Notification received via DBus:", id);

        // Get the notification from the model (added by FreedesktopNotifications::Notify)
        var notification = NotificationModel.getNotification(id);
        if (!notification) {
            console.warn("[NotificationService] Notification not found:", id);
            return;
        }

        // Create notification object for internal tracking
        var notif = {
            id: id,
            appId: notification.appId,
            title: notification.title,
            body: notification.body,
            icon: notification.icon,
            timestamp: new Date(notification.timestamp).toISOString(),
            read: false,
            category: "message",
            priority: "normal"
        };

        // Add to internal array
        notifications.push(notif);
        unreadCount++;

        console.log("[NotificationService] Notification processed:", id, notification.title);

        // Emit signal for UI updates
        notificationReceived(notif);

        // Play sound and vibrate (SINGLE source of audio/haptic feedback)
        if (soundEnabled && !AudioManager.dndEnabled) {
            AudioManager.playNotificationSound();
        }

        if (vibrationEnabled && !AudioManager.dndEnabled) {
            AudioManager.vibrate([50, 100, 50]);
        }
    }

    Component.onCompleted: {
        console.log("[NotificationService] Initialized");

        // Connect to NotificationModel signal for external notifications
        NotificationModel.notificationAdded.connect(_handleExternalNotification);

        if (!Platform.isLinux && !Platform.isMacOS) {
            _populateTestNotifications();
        }
    }
}
