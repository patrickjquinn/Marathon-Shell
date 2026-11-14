// SPDX-FileCopyrightText: 2004-2011 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-FileCopyrightText: 2013-2022 Jolla Ltd.
// SPDX-FileCopyrightText: 2019 Open Mobile Platform LLC.
// SPDX-License-Identifier: LGPL-2.1-only
/**
 * @file dbus-names.h
 * D-Bus Interface to the Mode Control Entity
 * <p>
 * This file is part of mce-dev
 * <p>
 * Copyright (c) 2004 - 2011 Nokia Corporation and/or its subsidiary(-ies).
 * Copyright (c) 2013 - 2022 Jolla Ltd.
 * Copyright (c) 2019 Open Mobile Platform LLC.
 * <p>
 * @author David Weinehall <david.weinehall@nokia.com>
 * @author Santtu Lakkala <ext-santtu.1.lakkala@nokia.com>
 * @author Victor Portnov <Victor.Portnov@teleca.com>
 * @author Simo Piiroinen <simo.piiroinen@jollamobile.com>
 * @author Kimmo Lindholm <kimmo.lindholm@eke.fi>
 *
 * These headers are free software; you can redistribute them
 * and/or modify them under the terms of the GNU Lesser General Public
 * License version 2.1 as published by the Free Software Foundation.
 *
 * These headers are distributed in the hope that they will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with these headers.
 * If not, see <http://www.gnu.org/licenses/>.
 */
#ifndef  MCE_DBUS_NAMES_H_
# define MCE_DBUS_NAMES_H_

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name MCE D-Bus Service
 *
 *@{
 */

/** MCE D-Bus service name
 *
 * @since mce 0.3
 */
# define MCE_SERVICE                       "com.nokia.mce"

/** MCE D-Bus Request interface
 *
 * @since mce 0.3
 */
# define MCE_REQUEST_IF                    "com.nokia.mce.request"
/** MCE D-Bus Signal interface
 *
 * @since mce 0.3
 */
# define MCE_SIGNAL_IF                     "com.nokia.mce.signal"
/** MCE D-Bus Request path
 *
 * @since mce 0.3
 */
# define MCE_REQUEST_PATH                  "/com/nokia/mce/request"
/** MCE D-Bus Signal path
 *
 * @since mce 0.3
 */
# define MCE_SIGNAL_PATH                   "/com/nokia/mce/signal"

/** The MCE D-Bus error interface; currently not used
 *
 * @since mce 0.3
 */
# define MCE_ERROR_FATAL                   "com.nokia.mce.error.fatal"
/** The D-Bus interface for invalid arguments; currently not used
 *
 * @since mce 0.3
 */
# define MCE_ERROR_INVALID_ARGS            "org.freedesktop.DBus.Error.InvalidArgs"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Radio State
 *
 *@{
 */

/** Query radio states
 *
 * @since mce 1.10.60
 *
 * Radio state bitmasks are constructed from:
 * - #MCE_RADIO_STATE_MASTER
 * - #MCE_RADIO_STATE_CELLULAR
 * - #MCE_RADIO_STATE_WLAN
 * - #MCE_RADIO_STATE_BLUETOOTH
 * - #MCE_RADIO_STATE_NFC
 * - #MCE_RADIO_STATE_FMTX
 *
 * @return uint32: bitmask of currently enabled radios
 */
# define MCE_RADIO_STATES_GET              "get_radio_states"

/** Request radio states change
 *
 * @since mce 1.10.60
 *
 * @note Aegis credential for Nokia N9: mce::DeviceModeControl
 *
 * Radio state bitmasks are constructed from:
 * - #MCE_RADIO_STATE_MASTER
 * - #MCE_RADIO_STATE_CELLULAR
 * - #MCE_RADIO_STATE_WLAN
 * - #MCE_RADIO_STATE_BLUETOOTH
 * - #MCE_RADIO_STATE_NFC
 * - #MCE_RADIO_STATE_FMTX
 *
 * Changes the radio state bits set in the mask parameter
 * to state given in the value parameter, i.e.
 *
 * current = (current & ~mask) | (value & mask)
 *
 * @param value uint32: bitmask of values to use
 * @param mask  uint32: bitmask of values to change
 */
# define MCE_RADIO_STATES_CHANGE_REQ       "req_radio_states_change"

/** Notify everyone that the radio states have changed
 *
 * @since mce 1.10.60
 *
 * Radio state bitmasks are constructed from:
 * - #MCE_RADIO_STATE_MASTER
 * - #MCE_RADIO_STATE_CELLULAR
 * - #MCE_RADIO_STATE_WLAN
 * - #MCE_RADIO_STATE_BLUETOOTH
 * - #MCE_RADIO_STATE_NFC
 * - #MCE_RADIO_STATE_FMTX
 *
 * @param current uint32: bitmask of currently active radios
 */
# define MCE_RADIO_STATES_SIG              "radio_states_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Call State
 *
 *@{
 */

/** Query the call state
 *
 * @since mce 1.8.1
 *
 * @return string: current call state, one of:
 * - #MCE_CALL_STATE_NONE
 * - #MCE_CALL_STATE_RINGING
 * - #MCE_CALL_STATE_ACTIVE
 * - #MCE_CALL_STATE_SERVICE
 *
 * @return string: current call type, one of:
 * - #MCE_NORMAL_CALL
 * - #MCE_EMERGENCY_CALL
 */
# define MCE_CALL_STATE_GET                "get_call_state"

/** Request call state change
 *
 * @since mce 1.8.1
 *
 * MCE tracks call state separately:
 * - from ofono modem and call properties
 * - for each client using issuing call state requests
 *
 * The overall call state will be "ringing" if at least
 * one of the tracked entities declares ringing state.
 *
 * The call type will be "emergency" it at least one of
 * the tracked entities declares emergency call type.
 *
 * If a client that has requested a call state change
 * drops from system bus, it will be handled as if
 * the client would have made a "none":"normal" request.
 *
 * @note Aegis credential for Nokia N9: mce::CallStateControl
 *
 * @param call_state string: call state to request, one of:
 * - #MCE_CALL_STATE_NONE
 * - #MCE_CALL_STATE_RINGING
 * - #MCE_CALL_STATE_ACTIVE
 * - #MCE_CALL_STATE_SERVICE
 *
 * @param call_type string: call type to request, one of:
 * - #MCE_NORMAL_CALL
 * - #MCE_EMERGENCY_CALL
 *
 * @return boolean: TRUE if the new call state was accepted, or
 *                  FALSE if the new call state was vetoed
 */
# define MCE_CALL_STATE_CHANGE_REQ         "req_call_state_change"

/** Notify everyone that the call state has changed
 *
 * @since mce 1.8.1
 *
 * @param call_state string: current call state, one of:
 * - #MCE_CALL_STATE_NONE
 * - #MCE_CALL_STATE_RINGING
 * - #MCE_CALL_STATE_ACTIVE
 * - #MCE_CALL_STATE_SERVICE
 *
 * @param call_type string: current call type, one of:
 * - #MCE_NORMAL_CALL
 * - #MCE_EMERGENCY_CALL
 */
# define MCE_CALL_STATE_SIG                "sig_call_state_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Display State
 *
 *@{
 */

/** Query the display status
 *
 * @since mce 1.5.21
 *
 * Display state is one of:
 *
 * @return string: current display state, one of:
 * - #MCE_DISPLAY_ON_STRING
 * - #MCE_DISPLAY_DIM_STRING
 * - #MCE_DISPLAY_OFF_STRING
 */
# define MCE_DISPLAY_STATUS_GET            "get_display_status"

/** Unblank display
 *
 * @since mce 0.5
 *
 * @note Applications should never make explicit display on requests.
 */
# define MCE_DISPLAY_ON_REQ                "req_display_state_on"

/**Dim display
 *
 * @since mce 1.6.20
 *
 * @note Applications should never make explicit display dim requests.
 */
# define MCE_DISPLAY_DIM_REQ               "req_display_state_dim"

/** Blank display
 *
 * @since mce 1.6.20
 *
 * @note Lockscreen is also activated when this call is made.
 */
# define MCE_DISPLAY_OFF_REQ               "req_display_state_off"

/** Set display to low power mode
 *
 * @since mce 1.33.0
 *
 * Blank screen via going through Display Low Power state.
 *
 * If LPM feature is not enabled, blanks display immediately.
 *
 * Low power mode is a display off sub state. From normal
 * display state signaling point of view it behaves just as
 * display off would. Depending on available hw support and
 * configuration extra ipc relevant for home screen / system
 * ui only might happen.
 */
# define MCE_DISPLAY_LPM_REQ               "req_display_state_lpm"

/** Notify everyone that the display is on/dimmed/off
 *
 * @since mce 1.5.21
 *
 * @param display_state  string: current display state, one of:
 * - #MCE_DISPLAY_ON_STRING
 * - #MCE_DISPLAY_DIM_STRING
 * - #MCE_DISPLAY_OFF_STRING
 */
# define MCE_DISPLAY_SIG                   "display_status_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Touchscreen And Keypad Lock State
 * @{
 */

/** Query the touchscreen/keypad lock mode
 *
 * @since mce 1.4.0
 *
 * @return string: current tklock state, one of:
 * - #MCE_TK_LOCKED
 * - #MCE_TK_SILENT_LOCKED
 * - #MCE_TK_LOCKED_DIM
 * - #MCE_TK_LOCKED_DELAY
 * - #MCE_TK_SILENT_LOCKED_DIM
 * - #MCE_TK_UNLOCKED
 * - #MCE_TK_SILENT_UNLOCKED
 */
# define MCE_TKLOCK_MODE_GET               "get_tklock_mode"

/** Request tklock mode change
 *
 * @since mce 1.4.0
 *
 * @note Aegis credential for Nokia N9: mce::TKLockControl
 *
 * @param mode string: requested tklock state, one of:
 * - #MCE_TK_LOCKED
 * - #MCE_TK_SILENT_LOCKED
 * - #MCE_TK_LOCKED_DIM
 * - #MCE_TK_LOCKED_DELAY
 * - #MCE_TK_SILENT_LOCKED_DIM
 * - #MCE_TK_UNLOCKED
 * - #MCE_TK_SILENT_UNLOCKED
 */
# define MCE_TKLOCK_MODE_CHANGE_REQ        "req_tklock_mode_change"

/** Signal that indicates that the touchscreen/keypad lock mode has changed
 *
 * @since mce 1.4.0
 *
 * @param mode string: current tklock state, one of:
 * - #MCE_TK_LOCKED
 * - #MCE_TK_SILENT_LOCKED
 * - #MCE_TK_LOCKED_DIM
 * - #MCE_TK_LOCKED_DELAY
 * - #MCE_TK_SILENT_LOCKED_DIM
 * - #MCE_TK_UNLOCKED
 * - #MCE_TK_SILENT_UNLOCKED
 */
# define MCE_TKLOCK_MODE_SIG               "tklock_mode_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Display Blank Prevention
 *
 *@{
 */

/** Prevent display from blanking
 *
 * @since mce 0.5
 *
 * Normal blanking timers are stopped for 60 seconds - under roughly
 * the following conditions:
 *
 * - Display is already on and lockscreen is not active
 *
 * - Display is already on, lockscreen is active but
 *   compositor has notified that user interaction is expected
 *   and the blanking prevent request originates from the same
 *   process that owns the topmost window on screen.
 *
 * The exact details are subject to change and clients showld
 * track #MCE_PREVENT_BLANK_ALLOWED_SIG signals to know when
 * making blank prevention calls are allowed/ignored (and query
 * the initial state with #MCE_PREVENT_BLANK_ALLOWED_GET).
 *
 * To keep display from blanking for longer periods, the client
 * needs to re-issue this call every 60 seconds.
 *
 * When application no longer wishes to keep display from blanking,
 * it should make a #MCE_CANCEL_PREVENT_BLANK_REQ method call.
 *
 * @note If client drops from the system bus, or misses the 60 second
 *       renew period, it is handled as if the client would have made
 *       a #MCE_CANCEL_PREVENT_BLANK_REQ method call.
 *
 * @note Previously mce waited exactly 60 seconds for renew calls
 *       which meant clients had to use shorter than 60 second
 *       renew periods to avoid hiccups. Since mce >= 1.93.0
 *       the hard limit is 65 seconds and thus clients can schedule
 *       renewing to occur once / 60 seconds.
 */
# define MCE_PREVENT_BLANK_REQ             "req_display_blanking_pause"

/** Cancel display blanking prevention
 *
 * @since mce 1.10.35
 */
# define MCE_CANCEL_PREVENT_BLANK_REQ      "req_display_cancel_blanking_pause"

/** Get current blank prevention status
 *
 * @since mce 1.51.0
 *
 * @return string: current blank prevention status, one of:
 * - #MCE_PREVENT_BLANK_ACTIVE_STRING
 * - #MCE_PREVENT_BLANK_INACTIVE_STRING
 */
# define MCE_PREVENT_BLANK_GET             "get_display_blanking_pause"

/** Notify everyone whether the display blanking is paused
 *
 * @since mce 1.51.0
 *
 * @param status string: current blank prevention status, one of:
 * - #MCE_PREVENT_BLANK_ACTIVE_STRING
 * - #MCE_PREVENT_BLANK_INACTIVE_STRING
 */
# define MCE_PREVENT_BLANK_SIG             "display_blanking_pause_ind"

/** Query whether MCE_PREVENT_BLANK_REQ request can be made
 *
 * @since 1.93.0
 *
 * See #MCE_PREVENT_BLANK_REQ for details.
 *
 * @return boolean: true for allowed, false for not allowed
 */
# define MCE_PREVENT_BLANK_ALLOWED_GET     "get_display_blanking_pause_allowed"

/** Notify change in whether MCE_PREVENT_BLANK_REQ request can be made
 *
 * @since 1.93.0
 *
 * See #MCE_PREVENT_BLANK_REQ for details.
 *
 * @param boolean: true for allowed, false for not allowed
 */
# define MCE_PREVENT_BLANK_ALLOWED_SIG     "display_blanking_pause_allowed_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Display Blanking Inhibit State
 *
 *@{
 */

/** Get current blank inhibition status
 *
 * @since mce 1.51.0
 *
 * @return string: current blanking inhibit status, one of:
 * - #MCE_INHIBIT_BLANK_ACTIVE_STRING
 * - #MCE_INHIBIT_BLANK_INACTIVE_STRING
 */
# define MCE_BLANKING_INHIBIT_GET          "get_display_blanking_inhibit"

/** Notify everyone whether the display blanking is inhibited
 *
 * @since mce 1.51.0
 *
 * @param status string: current blanking inhibit status, one of:
 * - #MCE_INHIBIT_BLANK_ACTIVE_STRING
 * - #MCE_INHIBIT_BLANK_INACTIVE_STRING
 */
# define MCE_BLANKING_INHIBIT_SIG          "display_blanking_inhibit_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Display Blanking Policy State
 *
 *@{
 */

/** Get current display blanking policy status
 *
 * @since mce 1.55.0
 *
 * @return string: current blanking policy, one of:
 * - #MCE_BLANKING_POLICY_DEFAULT_STRING
 * - #MCE_BLANKING_POLICY_NOTIFICATION_STRING
 * - #MCE_BLANKING_POLICY_ALARM_STRING
 * - #MCE_BLANKING_POLICY_CALL_STRING
 * - #MCE_BLANKING_POLICY_LINGER_STRING
 */
# define MCE_BLANKING_POLICY_GET           "get_display_blanking_policy"

/** Notify everyone when the display blanking policy changes
 *
 * @since mce 1.55.0
 *
 * @param policy string: current blanking policy, one of:
 * - #MCE_BLANKING_POLICY_DEFAULT_STRING
 * - #MCE_BLANKING_POLICY_NOTIFICATION_STRING
 * - #MCE_BLANKING_POLICY_ALARM_STRING
 * - #MCE_BLANKING_POLICY_CALL_STRING
 * - #MCE_BLANKING_POLICY_LINGER_STRING
 */
# define MCE_BLANKING_POLICY_SIG           "display_blanking_policy_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Power Save Mode
 *
 *@{
 */

/** Query the automatic power saving mode
 *
 * @since mce 1.10.44
 *
 * @return boolean: TRUE if automatic power saving mode is active, or
 *                  FALSE if automatic power saving mode is inactive
 */
# define MCE_PSM_STATE_GET                 "get_psm_state"

/** Notify everyone that the state of the automatic power saving mode changed
 *
 * @since mce 1.10.44
 *
 * @param active boolean: TRUE if automatic power saving mode is active, or
 *                        FALSE if automatic power saving mode is inactive
 */
# define MCE_PSM_STATE_SIG                 "psm_state_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Keypad Backlight Status
 *
 *@{
 */

/** Query key backlight state
 *
 * @since mce 1.10.30
 *
 * @return boolean: TRUE if the key backlight is on, or
 *                  FALSE if the key backlight is off
 */
# define MCE_KEY_BACKLIGHT_STATE_GET       "get_key_backlight_state"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Device Inactivity
 *
 *@{
 */

/** Query the inactivity status
 *
 * @since mce 1.5.2
 *
 * @return boolean: TRUE if the system is inactive, or
 *                  FALSE if the system is active
 */
# define MCE_INACTIVITY_STATUS_GET         "get_inactivity_status"

/** Notify everyone that the system is active/inactive
 *
 * @since mce 0.9.3
 *
 * @param active boolean: TRUE if the system is inactive, or
 *                        FALSE if the system is active
 */
# define MCE_INACTIVITY_SIG                "system_inactivity_ind"

/** Add an activity notification callback;
 *
 * @since mce 1.10.106
 *
 * The next user activity will trigger this callback.
 *
 * Callbacks are one-shot -- once the callback has been invoked,
 * it will be unregistered.
 *
 * @param service   string: The method call service
 * @param path      string: The method call path
 * @param interface string: The method call interface
 * @param name      string: The name of the method to call
 *
 * @return boolean: TRUE if registration was successful, or
 *                  FALSE if registration was a failure
 *                  (too many registered clients)
 */
# define MCE_ADD_ACTIVITY_CALLBACK_REQ     "add_activity_callback"

/** Remove any activity notification callback belonging to the calling process
 *
 * @since mce 1.10.106
 */
# define MCE_REMOVE_ACTIVITY_CALLBACK_REQ  "remove_activity_callback"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name CPU Keepalive
 *
 *@{
 */

/** Query the length of time late suspend can be blocked
 *
 * @since mce 1.12.8
 *
 * The idea is: if some process needs to do non-interactive
 * background processing, it can prevent the system from
 * entering late suspend by
 *
 * 1) get timer period via #MCE_CPU_KEEPALIVE_PERIOD_REQ call
 *
 * 2) call #MCE_CPU_KEEPALIVE_START_REQ
 *
 * 3) repeat #MCE_CPU_KEEPALIVE_START_REQ calls in interval
 *    that is shorter than the maximum obtained at (1)
 *
 * 4) call #MCE_CPU_KEEPALIVE_STOP_REQ when finished
 *
 * MCE keeps track of active clients and blocks late suspend
 * until all clients have called #MCE_CPU_KEEPALIVE_STOP_REQ,
 * lost D-Bus connection (exit, crash, ...) or all timeouts
 * have been missed.
 *
 * @since mce 1.23.7
 *
 * An unique within process tracking id can be passed to all
 * cpu keepalive related D-Bus method calls. This allows mce
 * to keep track of multiple, possibly overlapping keepalive
 * periods from one process.
 *
 * Old code that does not pass the tracking id still works
 * as long as the client process does not have multiple
 * overlapping periods at once.
 *
 * @param context string: "unique enough" tracking id
 *
 * @return int32: renew period in seconds
 */
# define MCE_CPU_KEEPALIVE_PERIOD_REQ      "req_cpu_keepalive_period"

/** Temporarily disable enter late suspend policy
 *
 * @since mce 1.12.8
 *
 * This method call must be repeated periodically to keep
 * the system from entering late suspend.
 *
 * The period length can be obtained via #MCE_CPU_KEEPALIVE_PERIOD_REQ.
 *
 * @note The boolean reply message is optional and will be sent
 *       only if requested.
 *
 * @param context string: "unique enough" tracking id
 *
 * @return boolean: TRUE on success, or FALSE in case of errors
 */
# define MCE_CPU_KEEPALIVE_START_REQ       "req_cpu_keepalive_start"

/** Allow normal enter late suspend policy again
 *
 * @since mce 1.12.8
 *
 * If a process blocks late suspend via #MCE_CPU_KEEPALIVE_START_REQ,
 * it must call #MCE_CPU_KEEPALIVE_STOP_REQ when background processing
 * is finished to enable normal late suspend policy again.
 *
 * @note The boolean reply message is optional and will be sent
 *       only if requested.
 *
 * @param context string: "unique enough" tracking id
 *
 * @return boolean: TRUE on success, or FALSE in case of errors
 */
# define MCE_CPU_KEEPALIVE_STOP_REQ        "req_cpu_keepalive_stop"

/** Signal wakeup from suspend due to aligned timer triggering
 *
 * @since mce 1.12.8
 *
 * @note This is reserved for use from dsme iphb module and is
 *       used for transferring ownership of rtc irq wakeup wakelock
 *       from dsme to mce.
 *
 * @note The boolean reply message is optional and will be sent
 *       only if requested.
 *
 * @return boolean: TRUE on success, or FALSE in case of errors
 */
# define MCE_CPU_KEEPALIVE_WAKEUP_REQ      "req_cpu_keepalive_wakeup"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name MCE Settings
 *
 *@{
 */

/** Query configuration value
 *
 * @since mce 1.12.15
 *
 * @param key string: name of the setting value to query
 *
 * @return variant: setting value, or error reply in case of errors
 */
# define MCE_CONFIG_GET                    "get_config"

/** Query all configuration values
 *
 * @since mce 1.83.0
 *
 * Get array of (key,value) pairs for all runtime changeable settings
 * that mce supports.
 *
 *     array [
 *        dict entry(
 *           string SETTING_KEY_NAME
 *           variant SETTING_KEY_VALUE
 *        )
 *        ...
 *     ]
 *
 * @return array of dict entries from setting key names and value variants
 */
# define MCE_CONFIG_GET_ALL                "get_config_all"

/** Set configuration value
 *
 * @since mce 1.12.15
 *
 * @param key string: setting key name
 * @param val variant: setting key value
 *
 * @return boolean: success, or error reply in case of failure
 */
# define MCE_CONFIG_SET                    "set_config"

/** Reset configuration values to default
 *
 * All config settings with keyname that matches the given substring
 * will be reset to configured defaults e.g. using "/" resets all
 * settings while using "/display/" resets only display related values.
 *
 * @since mce 1.42.0
 *
 * @param key string: setting key name / initial part of key name
 *
 * @return int32: number of changed settings, or -1 on failure
 */
# define MCE_CONFIG_RESET                  "reset_config"

/** Notify everyone that mce configuration value has changed
 *
 * @since mce 1.14.1
 *
 * @param key string: setting key name
 * @param val variant: setting key value
 */
# define MCE_CONFIG_CHANGE_SIG             "config_change_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Battery And Charging State
 *
 *@{
 */

/** Query current USB cable state
 *
 * @since mce 1.86.0
 *
 * @return string: current cable state, one of:
 * - #MCE_USB_CABLE_STATE_UNKNOWN
 * - #MCE_USB_CABLE_STATE_CONNECTED
 * - #MCE_USB_CABLE_STATE_DISCONNECTED
 */
# define MCE_USB_CABLE_STATE_GET           "get_usb_cable_state"

/** Signal that indicates that USB cable state has changed
 *
 * @since mce 1.86.0
 *
 * @param cable_state string: current cable state, one of:
 * - #MCE_USB_CABLE_STATE_UNKNOWN
 * - #MCE_USB_CABLE_STATE_CONNECTED
 * - #MCE_USB_CABLE_STATE_DISCONNECTED
 */
# define MCE_USB_CABLE_STATE_SIG           "usb_cable_state_ind"

/** Query current charger state
 *
 * @since mce 1.86.0
 *
 * @return string: current charger state, one of:
 * - #MCE_CHARGER_STATE_UNKNOWN
 * - #MCE_CHARGER_STATE_ON
 * - #MCE_CHARGER_STATE_OFF
 */
# define MCE_CHARGER_STATE_GET             "get_charger_state"

/** Signal that indicates that charger state has changed
 *
 * @since mce 1.86.0
 *
 * @param charger_state string: current charger state, one of:
 * - #MCE_CHARGER_STATE_UNKNOWN
 * - #MCE_CHARGER_STATE_ON
 * - #MCE_CHARGER_STATE_OFF
 */
# define MCE_CHARGER_STATE_SIG             "charger_state_ind"

/** Query current battery status
 *
 * @since mce 1.86.0
 *
 * @return string: current battery status, one of:
 * - #MCE_BATTERY_STATUS_UNKNOWN
 * - #MCE_BATTERY_STATUS_FULL
 * - #MCE_BATTERY_STATUS_OK
 * - #MCE_BATTERY_STATUS_LOW
 * - #MCE_BATTERY_STATUS_EMPTY
 */
# define MCE_BATTERY_STATUS_GET            "get_battery_status"

/** Signal that indicates that battery status has changed
 *
 * @since mce 1.86.0
 *
 * @param battery_status string: current battery status, one of:
 * - #MCE_BATTERY_STATUS_UNKNOWN
 * - #MCE_BATTERY_STATUS_FULL
 * - #MCE_BATTERY_STATUS_OK
 * - #MCE_BATTERY_STATUS_LOW
 * - #MCE_BATTERY_STATUS_EMPTY
 */
# define MCE_BATTERY_STATUS_SIG            "battery_status_ind"

/** Query current battery state
 *
 * @since mce 1.104.0
 *
 * @return string: current battery state, one of:
 * - #MCE_BATTERY_STATE_UNKNOWN
 * - #MCE_BATTERY_STATE_CHARGING
 * - #MCE_BATTERY_STATE_DISCHARGING
 * - #MCE_BATTERY_STATE_NOT_CHARGING
 * - #MCE_BATTERY_STATE_FULL
 */
#define MCE_BATTERY_STATE_GET              "get_battery_state"

/** Signal that indicates that battery state has changed
 *
 * @since mce 1.104.0
 *
 * @param battery_state string: current battery state, one of:
 * - #MCE_BATTERY_STATE_UNKNOWN
 * - #MCE_BATTERY_STATE_CHARGING
 * - #MCE_BATTERY_STATE_DISCHARGING
 * - #MCE_BATTERY_STATE_NOT_CHARGING
 * - #MCE_BATTERY_STATE_FULL
 */
#define MCE_BATTERY_STATE_SIG              "battery_state_ind"

/** Query current battery level
 *
 * @since mce 1.86.0
 *
 * @return int32: battery level percent, or #MCE_BATTERY_LEVEL_UNKNOWN
 */
# define MCE_BATTERY_LEVEL_GET             "get_battery_level"

/** Signal that indicates that battery level has changed
 *
 * @since mce 1.86.0
 *
 * @param bettery_level int32: battery level percent, or #MCE_BATTERY_LEVEL_UNKNOWN
 */
# define MCE_BATTERY_LEVEL_SIG             "battery_level_ind"

/** Query current charger type
 *
 * @since mce 1.102.0
 *
 * @return string: current charger type, one of:
 * - #MCE_CHARGER_TYPE_NONE
 * - #MCE_CHARGER_TYPE_USB
 * - #MCE_CHARGER_TYPE_DCP
 * - #MCE_CHARGER_TYPE_HVDCP
 * - #MCE_CHARGER_TYPE_CDP
 * - #MCE_CHARGER_TYPE_WIRELESS
 * - #MCE_CHARGER_TYPE_OTHER
 */
# define MCE_CHARGER_TYPE_GET             "get_charger_type"

/** Signal that indicates that charger type has changed
 *
 * @since mce 1.102.0
 *
 * @param charger_type string: current charger type, one of:
 * - #MCE_CHARGER_TYPE_NONE
 * - #MCE_CHARGER_TYPE_USB
 * - #MCE_CHARGER_TYPE_DCP
 * - #MCE_CHARGER_TYPE_HVDCP
 * - #MCE_CHARGER_TYPE_CDP
 * - #MCE_CHARGER_TYPE_WIRELESS
 * - #MCE_CHARGER_TYPE_OTHER
 */
# define MCE_CHARGER_TYPE_SIG             "charger_type_ind"

/** Query current charging hysteresis state
 *
 * @since mce 1.110.0
 *
 * @return string: charging hysteresis policy state, one of:
 * - #MCE_CHARGING_STATE_UNKNOWN
 * - #MCE_CHARGING_STATE_ENABLED
 * - #MCE_CHARGING_STATE_DISABLED
 */
# define MCE_CHARGING_STATE_GET           "get_charging_state"

/** Signal that indicates that charging hysteresis state has changed
 *
 * Charging hysteresis policy decision.
 *
 * @since mce 1.110.0
 *
 * @param string: charging hysteresis policy state, one of:
 * - #MCE_CHARGING_STATE_UNKNOWN
 * - #MCE_CHARGING_STATE_ENABLED
 * - #MCE_CHARGING_STATE_DISABLED
 */
# define MCE_CHARGING_STATE_SIG           "charging_state_ind"

/** Query charge-once-to-full policy override state
 *
 * @since mce 1.112.0
 *
 * @return string: charge-once-to-full policy override state, one of:
 * - #MCE_FORCED_CHARGING_UNKNOWN
 * - #MCE_FORCED_CHARGING_ENABLED
 * - #MCE_FORCED_CHARGING_DISABLED
 */
# define MCE_FORCED_CHARGING_GET           "get_forced_charging"

/** Request charge-once-to-full policy override state change
 *
 * @since mce 1.112.0
 * 
 * @note Override is automatically disabled if / when
 *       battery is full or charger is disconnected.
 *
 * @param value string: override state, one of:
 * - #MCE_FORCED_CHARGING_ENABLED
 * - #MCE_FORCED_CHARGING_DISABLED
 */
# define MCE_FORCED_CHARGING_REQ           "req_forced_charging"

/** Signal that indicates that charge-once-to-full policy override state has changed
 *
 * Charge-once-to-full policy override decision.
 *
 * @since mce 1.112.0
 *
 * @param string: charge-once-to-full policy state, one of:
 * - #MCE_FORCED_CHARGING_UNKNOWN
 * - #MCE_FORCED_CHARGING_ENABLED
 * - #MCE_FORCED_CHARGING_DISABLED
 */
# define MCE_FORCED_CHARGING_SIG           "forced_charging_ind"

/** Query whether charging can be suspended on this device
 *
 * @since mce 1.113.0
 *
 * @note As this is a matter of static configuration, the value
 *       returned does not change during mce runtime and thus
 *       there is related change signal.
 *
 * @return boolean: true if mce can be enable/disable charging, or
 *                  false if not
 */
# define MCE_CHARGING_SUSPENDABLE_GET      "get_charging_suspendable"

/*@}*/


/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name LED Control
 *
 *@{
 */

/** Activate a pre-defined LED pattern
 *
 * @since mce 1.5.0
 *
 * @note Aegis credential for Nokia N9: mce::LEDControl
 *
 * Available patterns depends on mce configuration.
 *
 * Non-existing patterns are ignored.
 *
 * See also: MCE_LED_PATTERN_ACTIVATED_SIG
 *
 * @param pattern string: led pattern name
 */
# define MCE_ACTIVATE_LED_PATTERN          "req_led_pattern_activate"

/** Deactivate a pre-defined LED pattern
 *
 * @since mce 1.5.0
 *
 * @note Aegis credential for Nokia N9: mce::LEDControl
 *
 * Available patterns depends on mce configuration.
 *
 * Non-existing patterns are ignored
 *
 * See also: MCE_LED_PATTERN_DEACTIVATED_SIG
 *
 * @param pattern string: led pattern name
 */
# define MCE_DEACTIVATE_LED_PATTERN        "req_led_pattern_deactivate"

/** Notify everyone that a led pattern has been activated
 *
 * @since mce 1.25.0
 *
 * @param activated_pattern string: led pattern name
 */
# define MCE_LED_PATTERN_ACTIVATED_SIG     "led_pattern_activated_ind"

/** Notify everyone that a led pattern has been deactivated
 *
 * @since mce 1.25.0
 *
 * @param deactivated_pattern string: led pattern name
 */
# define MCE_LED_PATTERN_DEACTIVATED_SIG   "led_pattern_deactivated_ind"

/** Allow activation of normal led patterns
 *
 * @since mce 1.5.0
 *
 * @note Aegis credential for Nokia N9: mce::LEDControl
 *
 * The current led stack is re-evaluated and also normal
 * led patterns are considered when choosing active pattern.
 *
 * @note Applications should never call this method. It is reserved
 *       for things like development time debugging and CSD test
 *       application (which needs to be sure patterns used by it
 *       do get priority over normal led patterns).
 */
# define MCE_ENABLE_LED                    "req_led_enable"

/** Deny actiovation of normal led patterns
 *
 * @since mce 1.5.0
 *
 * @note Aegis credential for Nokia N9: mce::LEDControl
 *
 * The current led stack is re-evaluated and normal led patterns
 * are ignored when choosing active pattern.
 *
 * @note Applications should never call this method. It is reserved
 *       for things like development time debugging and CSD test
 *       application (which needs to be sure patterns used by it
 *       do get priority over normal led patterns).
 */
# define MCE_DISABLE_LED                   "req_led_disable"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Input Event Handling Policy
 *
 *@{
 */

/** Get current touch screen input policy
 *
 * @since mce 1.87.0
 *
 * @return string: current touch input policy state, one of:
 * - #MCE_INPUT_POLICY_ENABLED
 * - #MCE_INPUT_POLICY_DISABLED
 */
# define MCE_TOUCH_INPUT_POLICY_GET        "get_touch_input_policy"

/** Indication for change of touch screen input policy
 *
 * @since mce 1.87.0
 *
 * @param input_state  string: current touch input input policy state, one of:
 * - #MCE_INPUT_POLICY_ENABLED
 * - #MCE_INPUT_POLICY_DISABLED
 */
# define MCE_TOUCH_INPUT_POLICY_SIG        "touch_input_policy_ind"

/** Get current volume key input policy
 *
 * @since mce 1.87.0
 *
 * @return string: current volkey input policy state, one of:
 * - #MCE_INPUT_POLICY_ENABLED
 * - #MCE_INPUT_POLICY_DISABLED
 */
# define MCE_VOLKEY_INPUT_POLICY_GET       "get_keypad_input_policy"

/** Indication for change of volume key input policy
 *
 * @since mce 1.87.0
 *
 * @param input_state  string: current volkey input input policy state, one of:
 * - #MCE_INPUT_POLICY_ENABLED
 * - #MCE_INPUT_POLICY_DISABLED
 */
# define MCE_VOLKEY_INPUT_POLICY_SIG       "keypad_input_policy_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Button Backlight Policy
 *
 *@{
 */

/** Get current button backlight state
 *
 * @since mce 1.90.0
 *
 * Returns true when button backlight is lit, false otherwise.
 *
 * @return boolean: TRUE for backlight is on, FALSE for off
 */
# define MCE_BUTTON_BACKLIGHT_GET          "get_button_backlight"

/** Request button backlight state change
 *
 * @since mce 1.90.0
 *
 * The button backlight is lit when policy permits is, at least one
 * D-Bus client has requested it, and the required control file
 * configuration has been provided.
 *
 * @param state boolean: TRUE for backlight on, FALSE for off
 */
# define MCE_BUTTON_BACKLIGHT_CHANGE_REQ   "req_button_backlight_change"

/** Request button backlight mode change
 *
 * @since mce 1.98.0
 *
 * For use from the CSD application button backlight verification test.
 *
 * Allows bypassing of the button backlight policy and explicitly turn
 * the backlight on or off.
 *
 * @param mode int32: #MCE_BUTTON_BACKLIGHT_MODE_OFF,
 *                    #MCE_BUTTON_BACKLIGHT_MODE_ON, or
 *                    #MCE_BUTTON_BACKLIGHT_MODE_POLICY
 */
# define MCE_BUTTON_BACKLIGHT_MODE_REQ     "req_button_backlight_mode"

/** Indication for change of button backlight state
 *
 * @since mce 1.90.0
 *
 * The state is true when button backlight is lit, false otherwise.
 *
 * @param state boolean: TRUE for backlight in on, FALSE for off
 */
# define MCE_BUTTON_BACKLIGHT_SIG          "sig_button_backlight_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Hardware Keyboard Availability
 *
 *@{
 */

/** Query HW keyboard availability
 *
 * @since mce 1.39.0
 *
 * Non-slidable keyboard present, or sliding keyboard present and opened
 *
 * Used for example in evaluating whether virtual keyboard
 * should be used or not.
 *
 * @return string: availability state, one of:
 * - #MCE_HARDWARE_KEYBOARD_UNDEF
 * - #MCE_HARDWARE_KEYBOARD_AVAILABLE
 * - #MCE_HARDWARE_KEYBOARD_NOT_AVAILABLE
 */
# define MCE_HARDWARE_KEYBOARD_STATE_GET   "keyboard_available_state_req"

/** Notify changes in HW keyboard availability
 *
 * @since mce 1.39.0
 *
 * Non-slidable keyboard present, or sliding keyboard present and opened
 *
 * @return string: availability state, one of:
 * - #MCE_HARDWARE_KEYBOARD_UNDEF
 * - #MCE_HARDWARE_KEYBOARD_AVAILABLE
 * - #MCE_HARDWARE_KEYBOARD_NOT_AVAILABLE
 */
# define MCE_HARDWARE_KEYBOARD_STATE_SIG   "keyboard_available_state_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Hardware Mouse Availability
 *
 *@{
 */

/** Query HW mouse availability
 *
 * @since mce 1.109.0
 *
 * Mouse present
 *
 * Used for example in evaluating whether mouse pointer
 * should be shown or not.
 *
 * @return string: availability state, one of:
 * - #MCE_HARDWARE_MOUSE_UNDEF
 * - #MCE_HARDWARE_MOUSE_AVAILABLE
 * - #MCE_HARDWARE_MOUSE_NOT_AVAILABLE
 */
# define MCE_HARDWARE_MOUSE_STATE_GET      "mouse_available_state_req"

/** Notify changes in HW mouse availability
 *
 * @since mce 1.109.0
 *
 * Mouse present
 *
 * @return string: availability state, one of:
 * - #MCE_HARDWARE_MOUSE_UNDEF
 * - #MCE_HARDWARE_MOUSE_AVAILABLE
 * - #MCE_HARDWARE_MOUSE_NOT_AVAILABLE
 */
# define MCE_HARDWARE_MOUSE_STATE_SIG      "mouse_available_state_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Sliding Keyboard State
 *
 *@{
 */

/** Query current sliding keyboard state
 *
 * @since mce 1.39.0
 *
 * @return string: keyboard state, one of:
 * - #MCE_SLIDING_KEYBOARD_OPEN
 * - #MCE_SLIDING_KEYBOARD_CLOSED
 * - #MCE_SLIDING_KEYBOARD_UNDEF
 */
# define MCE_SLIDING_KEYBOARD_STATE_GET    "keyboard_slide_state_req"

/** Notify sliding keyboard state changes
 *
 * @since mce 1.39.0
 *
 * @param state string: keyboard state, one of:
 * - #MCE_SLIDING_KEYBOARD_OPEN
 * - #MCE_SLIDING_KEYBOARD_CLOSED
 * - #MCE_SLIDING_KEYBOARD_UNDEF
 */
# define MCE_SLIDING_KEYBOARD_STATE_SIG    "keyboard_slide_state_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Interaction Between MCE And UI Components
 *
 *@{
 */

/** Signal for controlling compositor side display dimming
 *
 * @since mce 1.34.0
 *
 * In situations where there is not enough dynamic range available
 * to make the difference between "on" and "dimmed" display states
 * clear to user, mce sends this signal to instruct compositor to
 * complement the display backlight brightness based dimming by
 * blending the whole visible ui with an all black rectangle.
 *
 * The amount of requested dimming depends on hw specific
 * configuration and backlight brightness level in use.
 *
 * The requested fade animation duration is derived from what
 * mce would use for backlight brightness fade anination and
 * depends on mce side configuration.
 *
 * It is expected that compositor can and will cap both the
 * amount of dimming and transition length to some span that
 * makes sense from compositor point of view.
 *
 * @param dimming  int32: dimming percent
 * - 0 for normal, undimmed ui
 * - ...
 * - 100 completely blacked out ui
 * @param duration int32: fade animation duration [ms]
 */
# define MCE_FADER_OPACITY_SIG             "fader_opacity_ind"

/** Signal for notifying alarm ui about power key presses / device flip overs
 *
 * @since mce 1.26.0
 *
 * Used for silencing alarm via power key press / device flip over.
 *
 * @param event  string: event name, such as:
 * - #MCE_FEEDBACK_EVENT_POWERKEY
 * - #MCE_FEEDBACK_EVENT_FLIPOVER
 */
# define MCE_ALARM_UI_FEEDBACK_SIG         "alarm_ui_feedback_ind"

/** Signal for notifying call ui about power key presses / device flip overs
 *
 * @since mce 1.26.0
 *
 * Used for silencing incoming call via power key press / device flip over
 *
 * @param event  string: event name, such as:
 * - #MCE_FEEDBACK_EVENT_POWERKEY
 * - #MCE_FEEDBACK_EVENT_FLIPOVER
 */
# define MCE_CALL_UI_FEEDBACK_SIG          "call_ui_feedback_ind"

/** Inform mce that incoming call has been ignored by ui
 *
 * @since mce 1.19.0
 *
 * When there is an incoming call, mce reserves the power key
 * for alarm ui and silencing the ringing tone.
 *
 * This method can be used by the call ui to inform mce that the
 * call has been ignored and power key can again be used for display
 * power control even though there still are calls in ringing state.
 */
# define MCE_IGNORE_INCOMING_CALL_REQ      "req_ignore_incoming_call"

/** Signal for notifying systemui about power button etc related events
 *
 * @since mce 1.37.0
 *
 * @param event string: partly configurable and varies, but includes:
 * - #MCE_FEEDBACK_EVENT_HOMEKEY wake up to fingerprint detection,
 *     or toggle between home and app view
 * - #MCE_FEEDBACK_EVENT_UNLOCK switch ui to device unlock view
 */
# define MCE_POWER_BUTTON_TRIGGER          "power_button_trigger"

/** Method for sending tklock feedback from systemui to mce
 *
 * @since mce 1.10.88 (legacy)
 *
 * @deprecated Must not be used in application code and should be removed
 *             altogether both from mce and lipstick.
 *
 * @param status int32: tklock feedback, one of:
 * - #TKLOCK_UNLOCK
 * - #TKLOCK_RETRY
 * - #TKLOCK_TIMEOUT
 * - #TKLOCK_CLOSED
 */
# define MCE_TKLOCK_CB_REQ                 "tklock_callback"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Display Low Power Mode
 *
 *@{
 */

/** Request transition to lpm-off display state
 *
 * @since mce 1.82.3
 *
 * @note This method is not available in normal mce builds and
 *       it is meant strictly for debugging transitions to/from
 *       lpm display states only.
 */
# define MCE_DISPLAY_STATE_LPM_OFF_REQ     "req_display_state_lpm_off"

/** Request transition to lpm-on display state
 *
 * @since mce 1.82.3
 *
 * @note This method is not available in normal mce builds and
 *       it is meant strictly for debugging transitions to/from
 *       lpm display states only.
 */
# define MCE_DISPLAY_STATE_LPM_ON_REQ      "req_display_state_lpm_on"

/** Used for triggering UI transitions to/from LPM view
 *
 * @since mce 1.30.0
 *
 * The "Display Low Power Mode" is substate applicable when display
 * is logically in off state and lockscreen is active.
 *
 * The intent is that display gets powered up and lockscreen ui
 * with less decorations and suitable for low brightness display
 * is shown.
 *
 * Normal applications should not have any reason to follow these
 * signals.
 *
 * @param state string, one of:
 * - #MCE_LPM_UI_ENABLED
 * - #MCE_LPM_UI_DISABLED
 */
# define MCE_LPM_UI_MODE_SIG               "lpm_ui_mode_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name System Memory Pressure
 *
 *@{
 */

/** Method for querying current system memory pressure level
 *
 * @since mce 1.35.0
 *
 * @return level string, one of:
 * - #MCE_MEMORY_LEVEL_UNKNOWN
 * - #MCE_MEMORY_LEVEL_NORMAL
 * - #MCE_MEMORY_LEVEL_WARNING
 * - #MCE_MEMORY_LEVEL_CRITICAL
 */
# define MCE_MEMORY_LEVEL_GET              "get_memory_level"

/** Signal for notifying system memory pressure level changes
 *
 * @since mce 1.35.0
 *
 * @param level string, one of:
 * - #MCE_MEMORY_LEVEL_UNKNOWN
 * - #MCE_MEMORY_LEVEL_NORMAL
 * - #MCE_MEMORY_LEVEL_WARNING
 * - #MCE_MEMORY_LEVEL_CRITICAL
 */
# define MCE_MEMORY_LEVEL_SIG              "sig_memory_level_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Time Limited Display Wakeups
 *
 *@{
 */

/** Method for declaring start of exceptional display on state
 *
 * @since mce 1.29.0
 *
 * @param name     string: unique-enough identifier
 * @param duration int32: notification duration [ms]
 * @param extend   int32: extend due to user activity time [ms]
 */
# define MCE_NOTIFICATION_BEGIN_REQ        "notification_begin_req"

/** Method for declaring end of exceptional display on state
 *
 * @since mce 1.29.0
 *
 * @param name    string: unique-enough identifier
 * @param linger  int32: remain in display on time [ms]
 */
# define MCE_NOTIFICATION_END_REQ          "notification_end_req"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Content Adaptive Backlight Control Mode
 *
 *@{
 */

/** Query CABC mode
 *
 * @since mce 1.10.0
 *
 * @return string: current cabc mode, one of:
 * - #MCE_CABC_MODE_OFF
 * - #MCE_CABC_MODE_UI
 * - #MCE_CABC_MODE_STILL_IMAGE
 * - #MCE_CABC_MODE_MOVING_IMAGE
 */
# define MCE_CABC_MODE_GET                 "get_cabc_mode"

/** Request CABC mode change
 *
 * @since mce 1.10.0
 *
 * @note Content Adaptive Backlight Control has been supported only in
 *       maemo/meego phones made by Nokia.
 *
 * A non-functional skeleton interface is available unless suitable
 * hw and driver support exists along with relevant configuration.
 *
 * @param mode string: requested cabc mode, one of:
 * - #MCE_CABC_MODE_OFF
 * - #MCE_CABC_MODE_UI
 * - #MCE_CABC_MODE_STILL_IMAGE
 * - #MCE_CABC_MODE_MOVING_IMAGE
 *
 * @return string: updated cabc mode, one of:
 * - #MCE_CABC_MODE_OFF
 * - #MCE_CABC_MODE_UI
 * - #MCE_CABC_MODE_STILL_IMAGE
 * - #MCE_CABC_MODE_MOVING_IMAGE
 */
# define MCE_CABC_MODE_REQ                 "req_cabc_mode"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Color Profile
 *
 *@{
 */

/** Query the current color profile id
 *
 * @since mce 1.11.2
 *
 * @return string: the current profile id
 */
# define MCE_COLOR_PROFILE_GET             "get_color_profile"

/** Query the list of the available color profile ids
 *
 * @since mce 1.11.2
 *
 * Apart from built-in "hardcoded" the available color profiles
 * depends on mce configuration.
 *
 * @return array of strings: supported color profile ids
 */
# define MCE_COLOR_PROFILE_IDS_GET         "get_color_profile_ids"

/** Request color profile change
 *
 * @since mce 1.11.2
 *
 * @note Currently the color profiles are not supported and a skeleton
 *       API is available solely for backwards compatibility.
 *
 * @note Aegis credential for Nokia N9: mce::ColorProfileControl
 *
 * @param mode string: requested color profile id
 */
# define MCE_COLOR_PROFILE_CHANGE_REQ      "req_color_profile_change"

/** Notify everyone that the color profile has changed
 *
 * @since mce 1.11.2
 *
 * @note Color profiles have been supported only in maemo/meego phones
 *       made by Nokia.
 *
 * @deprecated Only a skeleton functionality is provided for backwards
 *             compatibility.
 *
 * @param mode string: current color profile id
 */
# define MCE_COLOR_PROFILE_SIG             "color_profile_ind"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Miscellaneous
 *
 *@{
 */

/** Query MCE version
 *
 * @since mce 1.1.6
 *
 * @return string: MCE version
 */
# define MCE_VERSION_GET                   "get_version"

/** Request powerkey event triggering
 *
 * @since mce 1.5.3 (implemented)
 * @since mce 1.10.54 (argument changed from boolean to uint32)
 *
 * @note Aegis credential for Nokia N9: mce::DeviceModeControl
 *
 * @note Intended for use from automated qa testing only.
 *
 * @param type uint32: power key event to trigger, one of:
 * - #MCE_POWERKEY_EVENT_SHORT_PRESS
 * - #MCE_POWERKEY_EVENT_LONG_PRESS
 * - #MCE_POWERKEY_EVENT_DOUBLE_PRESS
 */
# define MCE_TRIGGER_POWERKEY_EVENT_REQ    "req_trigger_powerkey_event"

/** Get amount of time spent in each display state
 *
 * @since mce 1.74.0
 *
 * Used for: Debugging power drain issues, QA reporting, etc.
 *
 * After MCE process starts up, it keeps track of the number of times
 * various display states have been entered and total time spent in
 * each state. Time before mce startup gets accounted to "undefined"
 * display state.
 *
 * The data returned is - in dbus terms - array of dictionary entries
 * having display state name as a key and total time and entry count
 * as value.
 *
 *     array [
 *        dict entry(
 *           string DISPLAY_STATE_NAME
 *           struct {
 *              int64 MS_SPENT_IN_THE_STATE
 *              int64 ENTRY_COUNT_TO_THE_STATE
 *           }
 *        )
 *        ...
 *     ]
 *
 * @return array of entries as described above
 */
# define MCE_DISPLAY_STATS_GET             "get_display_stats"

/** Query current uptime and time spent in suspend
 *
 * @since mce 1.65.0
 *
 * Used for: Automated suspend testing, QA reporting, etc.
 *
 * Basically:
 * - uptime is taken from CLOCK_BOOTTIME
 * - suspend time is taken from CLOCK_MONOTONIC - CLOCK_BOOTTIME
 *
 * @return int64: uptime_ms
 * @return int64: suspend_ms
 */
# define MCE_SUSPEND_STATS_GET             "get_suspend_stats"

/** Query current logging verbosity
 *
 * @since mce 1.71.0
 *
 * @return int32: syslog compatible verbosity level:
 * - 0 == LOG_EMERG
 * - ...
 * - 7 == LOG_DEBUG
 */
# define MCE_VERBOSITY_GET                 "get_verbosity"

/** Change current logging verbosity
 *
 * @since mce 1.71.0
 *
 * @param verbosity int32: syslog compatible verbosity level:
 * - 0 == LOG_EMERG
 * - ...
 * - 7 == LOG_DEBUG
 */
# define MCE_VERBOSITY_REQ                 "set_verbosity"

/*@}*/

#endif /* MCE_DBUS_NAMES_H_ */
