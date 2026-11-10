// SPDX-FileCopyrightText: 2004-2011 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-FileCopyrightText: 2012-2022 Jolla Ltd.
// SPDX-FileCopyrightText: 2019 Open Mobile Platform LLC.
// SPDX-License-Identifier: LGPL-2.1-only
/**
 * @file mode-names.h
 * Defines for names of various modes and submodes for Mode Control Entity
 * <p>
 * This file is part of mce-dev
 * <p>
 * Copyright (c) 2004 - 2011 Nokia Corporation and/or its subsidiary(-ies).
 * Copyright (c) 2012 - 2022 Jolla Ltd.
 * Copyright (c) 2019 Open Mobile Platform LLC.
 * <p>
 * @author David Weinehall <david.weinehall@nokia.com>
 * @author Tapio Rantala <ext-tapio.rantala@nokia.com>
 * @author Vesa Halttunen <vesa.halttunen@jollamobile.com>
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
#ifndef  MCE_MODE_NAMES_H_
# define MCE_MODE_NAMES_H_

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Radio State Constants
 *
 *@{
 */

/** Master switch; set - radios enabled, unset - radios disabled
 *
 * @since mce 1.10.60
 *
 * @note Effectively is an alias for connman offline mode property.
 *       Chamges to offline mode are reflected to mce master radio
 *       bit and vise versa.
 */
# define MCE_RADIO_STATE_MASTER                  (1 << 0)

/** Cellular; set - enabled, unset - disabled
 *
 * @since mce 1.10.60
 *
 * @note Currently this exists for backwards compatibility only.
 */
# define MCE_RADIO_STATE_CELLULAR                (1 << 1)

/** WLAN; set - enabled, unset - disabled
 *
 * @since mce 1.10.60
 *
 * @note Currently this exists for backwards compatibility only.
 */
# define MCE_RADIO_STATE_WLAN                    (1 << 2)

/** Bluetooth; set - enabled, unset - disabled
 *
 * @since mce 1.10.60
 *
 * @note Currently this exists for backwards compatibility only.
 */
# define MCE_RADIO_STATE_BLUETOOTH               (1 << 3)

/** NFC; set - enabled, unset - disabled
 *
 * @since mce 1.10.93
 *
 * @note Currently this exists for backwards compatibility only.
 */
# define MCE_RADIO_STATE_NFC                     (1 << 4)

/** FM transmitter; set - enabled, unset - disabled
 *
 * @since mce 1.10.93
 *
 * @note Currently this exists for backwards compatibility only.
 */
# define MCE_RADIO_STATE_FMTX                    (1 << 5)

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Call State Constants
 *
 *@{
 */

/** No ongoing call
 *
 * @since mce 1.8.4
 */
# define MCE_CALL_STATE_NONE                     "none"

/** Call ringing
 *
 * @since mce 1.8.29
 */
# define MCE_CALL_STATE_RINGING                  "ringing"

/** Call on-going
 *
 * @since mce 1.8.29
 */
# define MCE_CALL_STATE_ACTIVE                   "active"

/** Service operation on-going
 *
 * @since mce 1.8.29
 *
 * @deprecated No longer in active use.
 *
 * Use to prevent calls from being initiated;
 * will not prevent emergency calls
 */
# define MCE_CALL_STATE_SERVICE                  "service"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Call Type Constants
 *
 *@{
 */

/** Normal call
 *
 * @since mce 1.8.4
 */
# define MCE_NORMAL_CALL                         "normal"

/** Emergency call
 *
 * @since mce 1.8.4
 */
# define MCE_EMERGENCY_CALL                      "emergency"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Touchscreen And Keypad Lock State Constants
 *
 *@{
 */

/** Touchscreen/Keypad locked
 *
 * @since mce 1.4.5
 */
# define MCE_TK_LOCKED                           "locked"

/** Touchscreen/Keypad silently locked
 *
 * @since mce 1.4.15
 *
 * @deprecated Handled as an alias for #MCE_TK_LOCKED
 */
# define MCE_TK_SILENT_LOCKED                    "silent-locked"

/** Touchscreen/Keypad locked with fadeout
 *
 * @since mce 1.4.15
 *
 * @deprecated Handled as an alias for #MCE_TK_LOCKED
 */
# define MCE_TK_LOCKED_DIM                       "locked-dim"

/** Touchscreen/Keypad locked with delay
 *
 * @since mce 1.12.2
 *
 * @deprecated Handled as an alias for #MCE_TK_LOCKED
 */
# define MCE_TK_LOCKED_DELAY                     "locked-delay"

/** Touchscreen/Keypad silently locked with fadeout
 *
 * @since mce 1.4.15
 *
 * @deprecated Handled as an alias for #MCE_TK_LOCKED
 */
# define MCE_TK_SILENT_LOCKED_DIM                "silent-locked-dim"

/** Touchscreen/Keypad unlocked
 *
 * @since mce 1.4.5
 */
# define MCE_TK_UNLOCKED                         "unlocked"

/** Touchscreen/Keypad silently unlocked
 *
 * @since mce 1.6.33
 *
 * @deprecated Handled as an alias for #MCE_TK_UNLOCKED
 */
# define MCE_TK_SILENT_UNLOCKED                  "silent-unlocked"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Display State Constants
 *
 *@{
 */

/** Display state name for display on
 *
 * @since mce 1.5.21
 */
# define MCE_DISPLAY_ON_STRING                   "on"

/** Display state name for display dim
 *
 * @since mce 1.5.21
 */
# define MCE_DISPLAY_DIM_STRING                  "dimmed"

/** Display state name for display off
 *
 * @since mce 1.5.21
 */
# define MCE_DISPLAY_OFF_STRING                  "off"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Blank Prevention State Constants
 *
 *@{
 */

/** Blank prevent state name for active
 *
 * @since mce 1.51.0
 */
# define MCE_PREVENT_BLANK_ACTIVE_STRING         "active"

/** Blank prevent state name for inactive
 *
 * @since mce 1.51.0
 */
# define MCE_PREVENT_BLANK_INACTIVE_STRING       "inactive"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Blanking Inhibit State Constants
 *
 *@{
 */

/** Blank inhibit state name for active
 *
 * @since mce 1.51.0
 */
# define MCE_INHIBIT_BLANK_ACTIVE_STRING         "active"

/** Blank inhibit state name for inactive
 *
 * @since mce 1.51.0
 */
# define MCE_INHIBIT_BLANK_INACTIVE_STRING       "inactive"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Blanking Policy State Constants
 *
 *@{
 */

/** Default blanking policy active
 *
 * @since mce 1.55.0
 */
# define MCE_BLANKING_POLICY_DEFAULT_STRING      "default"

/** Default blanking policy disabled due to notifications
 *
 * @since mce 1.55.0
 */
# define MCE_BLANKING_POLICY_NOTIFICATION_STRING "notification"

/** Default blanking policy disabled due to alarm dialog state
 *
 * @since mce 1.55.0
 */
# define MCE_BLANKING_POLICY_ALARM_STRING        "alarm"

/** Default blanking policy disabled due to call state
 *
 * @since mce 1.55.0
 */
# define MCE_BLANKING_POLICY_CALL_STRING         "call"

/** Default blanking policy is about to be restored
 *
 * @since mce 1.55.0
 */
# define MCE_BLANKING_POLICY_LINGER_STRING       "linger"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name CABC Mode Constants
 *
 *@{
 */

/** CABC name for CABC disabled
 *
 * @since mce 1.8.88
 */
# define MCE_CABC_MODE_OFF                       "off"

/** CABC name for UI mode
 *
 * @since mce 1.8.88
 */
# define MCE_CABC_MODE_UI                        "ui"

/** CABC name for still image mode
 *
 * @since mce 1.8.88
 */
# define MCE_CABC_MODE_STILL_IMAGE               "still-image"

/** CABC name for moving image mode
 *
 * @since mce 1.8.88
 */
# define MCE_CABC_MODE_MOVING_IMAGE              "moving-image"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Power Key Trigger Constants
 *
 *@{
 */

/** Simulate single powerkey press
 *
 * @since mce 1.10.54
 */
# define MCE_POWERKEY_EVENT_SHORT_PRESS          (0u)

/** Simulate long powerkey press
 *
 * @since mce 1.10.54
 */
# define MCE_POWERKEY_EVENT_LONG_PRESS           (1u)

/** Simulate double powerkey press
 *
 * @since mce 1.10.54
 */
# define MCE_POWERKEY_EVENT_DOUBLE_PRESS         (2u)

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name USB Cable State Constants
 *
 *@{
 */

/** USB cable state is not known
 *
 * @since mce 1.86.0
 */
# define MCE_USB_CABLE_STATE_UNKNOWN             "unknown"

/** USB cable is connected
 *
 * @since mce 1.86.0
 */
# define MCE_USB_CABLE_STATE_CONNECTED           "connected"

/** USB cable is disconnected
 *
 * @since mce 1.86.0
 */
# define MCE_USB_CABLE_STATE_DISCONNECTED        "disconnected"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Charger State Constants
 *
 *@{
 */

/** Charger state is not known
 *
 * @since mce 1.86.0
 */
# define MCE_CHARGER_STATE_UNKNOWN               "unknown"

/** Charger is active
 *
 * @since mce 1.86.0
 */
# define MCE_CHARGER_STATE_ON                    "on"

/** Charger is inactive
 *
 * @since mce 1.86.0
 */
# define MCE_CHARGER_STATE_OFF                   "off"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Charger Type Constants
 *
 *@{
 */

/** No charger is active
 *
 * @since mce 1.102.0
 */
# define MCE_CHARGER_TYPE_NONE                   "none"

/** Standard down port (pc/hub) charger is active
 *
 * @since mce 1.102.0
 */
# define MCE_CHARGER_TYPE_USB                    "usb"

/** Dedicated charging port (wall) charger is active
 *
 * @since mce 1.102.0
 */
# define MCE_CHARGER_TYPE_DCP                    "dcp"

/** High voltage DCP charger is active
 *
 * @since mce 1.102.0
 */
# define MCE_CHARGER_TYPE_HVDCP                  "hvdcp"

/** Charging Downstream Port charger is active
 *
 * @since mce 1.102.0
 */
# define MCE_CHARGER_TYPE_CDP                    "cdp"

/** Wireless charger is active
 *
 * @since mce 1.102.0
 */
# define MCE_CHARGER_TYPE_WIRELESS               "wireless"

/** Other kind of charger is active
 *
 * @since mce 1.102.0
 */
# define MCE_CHARGER_TYPE_OTHER                  "other"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Charging Hysteresis State Constants
 *
 *@{
 */

/** Charging hysteresis policy state is not known
 *
 * @since mce 1.110.0
 */
# define MCE_CHARGING_STATE_UNKNOWN              "unknown"

/** Charging hysteresis policy allows charging
 *
 * @since mce 1.110.0
 */
# define MCE_CHARGING_STATE_ENABLED              "enabled"

/** Charging hysteresis policy denies charging
 *
 * @since mce 1.110.0
 */
# define MCE_CHARGING_STATE_DISABLED             "disabled"
/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Charge-once-to-full policy override constants
 *
 *@{
 */

/** Charge-once-to-full policy override state is not known
 *
 * @since mce 1.112.0
 */
# define MCE_FORCED_CHARGING_UNKNOWN              "unknown"

/** Charge-once-to-full policy override has been activated
 *
 * @since mce 1.112.0
 */
# define MCE_FORCED_CHARGING_ENABLED              "enabled"

/** Charge-once-to-full policy override has been deactivated
 *
 * @since mce 1.112.0
 */
# define MCE_FORCED_CHARGING_DISABLED             "disabled"
/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Battery Status Constants
 *
 * These values match legacy maemo (bme) battery status values.
 *
 *@{
 */

/** Battery status is not known
 *
 * @since mce 1.86.0
 */
# define MCE_BATTERY_STATUS_UNKNOWN              "unknown"

/** Battery is full
 *
 * @since mce 1.86.0
 */
# define MCE_BATTERY_STATUS_FULL                 "full"

/** Battery is neither full nor empty
 *
 * @since mce 1.86.0
 */
# define MCE_BATTERY_STATUS_OK                   "ok"

/** Battery is low on power
 *
 * @since mce 1.86.0
 */
# define MCE_BATTERY_STATUS_LOW                  "low"

/** Battery is empty
 *
 * @since mce 1.86.0
 */
# define MCE_BATTERY_STATUS_EMPTY                "empty"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Battery State Constants
 *
 * These values match linux power supply device status values.
 *
 *@{
 */

/** Battery state is not known
 *
 * @since mce 1.104.0
 */
# define MCE_BATTERY_STATE_UNKNOWN               "unknown"

/** Battery is currently discharging
 *
 * Charger is disconnected, battery is discharging.
 *
 * @since mce 1.104.0
 */
# define MCE_BATTERY_STATE_DISCHARGING           "discharging"

/** Battery is currently charging
 *
 * Charger is connected, battery is charging.
 *
 * @since mce 1.104.0
 */
# define MCE_BATTERY_STATE_CHARGING              "charging"

/** Battery is not getting charged
 *
 * Charger is connected, battery is not getting charged.
 *
 * @since mce 1.104.0
 */
# define MCE_BATTERY_STATE_NOT_CHARGING          "not_charging"

/** Battery is fully charged
 *
 * Charger is connected, battery is full.
 *
 * @since mce 1.104.0
 */
# define MCE_BATTERY_STATE_FULL                  "full"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Battery Level Constants
 *
 *@{
 */

/** Battery level percentage is not known
 *
 * @since mce 1.86.0
 */
# define MCE_BATTERY_LEVEL_UNKNOWN               (-1)

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Input Policy State Constants
 *
 *@{
 */

/** Input events should be processed normally
 *
 * @since mce 1.87.0
 */
# define MCE_INPUT_POLICY_ENABLED                "enabled"

/** Input events should be ignored
 *
 * @since mce 1.87.0
 */
# define MCE_INPUT_POLICY_DISABLED               "disabled"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Hardware Keyboard Availability Constants
 *
 *@{
 */

/** Hardware Keyboard availability is not known
 *
 * @since mce 1.39.0
 */
# define MCE_HARDWARE_KEYBOARD_UNDEF             "undef"

/** Hardware Keyboard is available
 *
 * @since mce 1.39.0
 */
# define MCE_HARDWARE_KEYBOARD_AVAILABLE         "available"

/** Hardware Keyboard is not available
 *
 * @since mce 1.39.0
 */
# define MCE_HARDWARE_KEYBOARD_NOT_AVAILABLE     "not-available"
/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Hardware Mouse Availability Constants
 *
 *@{
 */

/** Hardware Mouse availability is not known
 *
 * @since mce 1.109.0
 */
# define MCE_HARDWARE_MOUSE_UNDEF                "undef"

/** Hardware Mouse is available
 *
 * @since mce 1.109.0
 */
# define MCE_HARDWARE_MOUSE_AVAILABLE            "available"

/** Hardware Mouse is not available
 *
 * @since mce 1.109.0
 */
# define MCE_HARDWARE_MOUSE_NOT_AVAILABLE        "not-available"
/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Feedback Event Name Constants
 *
 *@{
 */

/** Notify that an application should handle powerkey press
 *
 * @since mce 1.26.0
 *
 * Normally MCE handles powerkey presses internally, however
 * there are some exceptions - for example  during alarms and
 * incoming calls - where reacting to power key press is
 * delegated to application ui relevant to the context.
 *
 * See:
 * - #MCE_ALARM_UI_FEEDBACK_SIG
 * - #MCE_CALL_UI_FEEDBACK_SIG
 */
# define MCE_FEEDBACK_EVENT_POWERKEY             "powerkey"

/** Notify that an application should handle device flipover
 *
 * @since mce 1.26.0
 *
 * While there are incoming calls or ringing alarms, MCE does
 * device flipover detection. Reacting to such "sensor gestures"
 * is delegated to application ui relevant to the context.
 *
 * See:
 * - #MCE_ALARM_UI_FEEDBACK_SIG
 * - #MCE_CALL_UI_FEEDBACK_SIG
 */
# define MCE_FEEDBACK_EVENT_FLIPOVER             "flipover"

/** Request lockscreen ui to switch to device unlock view
 *
 * @since mce 1.37.0
 *
 * When MCE bumps into situation where removing tklock is
 * requested while device is locked, it asks ui to switch
 * into device unlock view instead of deactivating tklock.
 *
 * See:
 * - #MCE_POWER_BUTTON_TRIGGER
 *
 * @note The "double-power-key" value is just unfortunate
 *       historical artefact that can't be changed without
 *       causing a D-Bus API break.
 */
# define MCE_FEEDBACK_EVENT_UNLOCK               "double-power-key"

/** Notify lipstick about homekey presses
 *
 * @since mce 1.82.0
 *
 * Artefact from tk7001 adaptation: The fingerprint sensor
 * doubles as home key. To facilitate "wakeup display and
 * activate fingerprint sensor" type activity homekey
 * handling is divided in two parts: 1st mce subjects the
 * press to similar unblanking rules as what is done to
 * the powerkey and then after/when display is powered up
 * reaction to the homekey is delegated to lipstick.
 *
 * See:
 * - #MCE_POWER_BUTTON_TRIGGER
 */
# define MCE_FEEDBACK_EVENT_HOMEKEY              "home-key"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Sliding Keyboard Availability Constants
 *
 * Used for example in evaluating whether virtual keyboard
 * should be used or not.
 *
 * See:
 * - #MCE_SLIDING_KEYBOARD_STATE_GET
 * - #MCE_SLIDING_KEYBOARD_STATE_SIG
 *
 *@{
 */

/** Sliding Keyboard state is not known
 *
 * @since mce 1.39.0
 */
# define MCE_SLIDING_KEYBOARD_UNDEF              "undef"

/** Sliding Keyboard is opened
 *
 * @since mce 1.39.0
 */
# define MCE_SLIDING_KEYBOARD_OPEN               "open"

/** Sliding Keyboard is closed
 *
 * @since mce 1.39.0
 */
# define MCE_SLIDING_KEYBOARD_CLOSED             "closed"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Display Low Power Mode Constants
 *
 *@{
 */

/** Display Low Power Mode is Enabled
 *
 * @since mce 1.30.0
 */
# define MCE_LPM_UI_ENABLED                      "enabled"

/** Display Low Power Mode is Disabled
 *
 * @since mce 1.30.0
 */
# define MCE_LPM_UI_DISABLED                     "disabled"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name System Memory Pressure Constants
 *
 *@{
 */

/** System memory use is at normal level
 *
 * @since mce 1.35.0
 */
# define MCE_MEMORY_LEVEL_NORMAL                 "normal"

/** System memory use is above normal level
 *
 * @since mce 1.35.0
 *
 * Signifies: Unnecesary resources should be released.
 */
# define MCE_MEMORY_LEVEL_WARNING                "warning"

/** System memory use is at critical level
 *
 * @since mce 1.35.0
 *
 * Signifies: Unnecessary processes should exit. Non-critical
 * processes can be expected to get terminated by kernel side
 * out of memory killer.
 */
# define MCE_MEMORY_LEVEL_CRITICAL               "critical"

/** System memory use can't be evaluated
 *
 * @since mce 1.35.0
 *
 * Signifies: Kernel does not provide memnotify interface
 * and/or memory use limits have not been defined in mce
 * configuration.
 */
# define MCE_MEMORY_LEVEL_UNKNOWN                "unknown"

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name TKLock status replies from SystemUI
 *
 *@{
 */

/** TKLock was unlocked by the user
 *
 * @since mce 1.10.92 (legacy)
 */
# define TKLOCK_UNLOCK                           1
/** TKLock unlock attempt failed
 *
 * @since mce 1.10.92 (legacy)
 *
 * @deprecated Ignored by MCE
 */
# define TKLOCK_RETRY                            2

/** Attempt to open TKLock timed out
 *
 * @since mce 1.10.92 (legacy)
 *
 * @deprecated Ignored by MCE
 */
# define TKLOCK_TIMEOUT                          3
/** TKLock closed on request from mce
 *
 * @since mce 1.10.92 (legacy)
 */
# define TKLOCK_CLOSED                           4

/*@}*/

/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
/** @name Button backlight operation modes
 *
 *@{
 */

/** Button backlight should be turned off
 *
 * @since mce 1.98.0
 */
#define MCE_BUTTON_BACKLIGHT_MODE_OFF    0

/** Button backlight should be turned on
 *
 * @since mce 1.98.0
 */
#define MCE_BUTTON_BACKLIGHT_MODE_ON     1

/** Button backlight should be turned on/off according to policy
 *
 * @since mce 1.98.0
 */
#define MCE_BUTTON_BACKLIGHT_MODE_POLICY 2

/*@}*/

#endif /* MCE_MODE_NAMES_H_ */
