/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Keyboard Driver for Blackberry Keyboards BBQ10 from arturo182. Software written by wallComputer.
 * bbq10kbd_codes.h: Keyboard Layout and Scancodes-Keycodes mapping.
 */

#ifndef BBQ10KBD_FEATHERWING_CODES_H_
#define BBQ10KBD_FEATHERWING_CODES_H_

/*
 *					BBQ20KBD PMOD KEYBOARD LAYOUT
 *
 *	+------+-----+----+----+----+----+----+-----+-----+-------+
 *	|      |          |BR     ↑TPY-       |           |       |
 *	| Ctrl |   PgDn   |←TPX- BL(HOME)TPX+→|   PgUp    | MENU  |
 *	|      |          |       ↓TPY+       |           |       |
 *	+------+-----+----+----+----+----+----+-----+-----+-------+
 *	|                                                         |
 *	+------+-----+----+----+----+----+----+-----+-----+-------+
 *	|#     |1    |2   |3   |(   |   )|_   |    -|    +|      @|
 *	|  Q   |  W  | E  | R  | T  |  Y |  U |  I  |  O  |   P   |
 *	|      |     |PgDn|PgUp|   \|UP  |^   |=    |{    |}      |
 *	+------+-----+----+----+----+----+----+-----+-----+-------+
 *	|*     |4    |5   |6   |/   |   :|;   |    '|    "|    ESC|
 *	|  A   |  S  | D  | F  | G  |  H |  J |  K  |  L  |  BKSP |
 *	|     ?|     |   [|   ]|LEFT|HOME|RGHT|V+   |V-   |DLT    |
 *	+------+-----+----+----+----+----+----+-----+-----+-------+
 *	|      |7    |8   |9   |?   |   !|,   |    .|    `|       |
 *	|LFTALT|  Z  | X  | C  | V  |  B |  N |  M  |  $  | ENTER |
 *	|      |   K+|  K-|   °|   <|DOWN|>   |MENU |Vx   |       |
 *	+------+-----+----+----+----+----+----+-----+-----+-------+
 *	|            |0   |TAB                |     |             |
 *	| LEFT_SHIFT | ~  |       SPACE       |RTALT| RIGHT_SHIFT |
 *	|            |  Kx|                  &|     |             |
 *	+------------+----+-------------------+-----+-------------+
 *
 * Notes:
 * Most Important to know:
 * To present a character as mentioned above a key in the above layout, use LFTALT + Key.
 * To present a character as mentioned below a key in the above layout, use RTALT + Key.
 *
 * Changes from arturo182's layout, if you are used to that, it's good to know these changes.
 * 1. Sym Key (Scancode 0x1D) on Keyboard is mapped to RTALT.
 * 3. The external buttons on the Keyboard Featherwing have been changed as below:
 *__3.1 Leftmost Button changed from Menu Key to Left Ctrl Key.
 *__3.2 Innet Left Button changed from Left Ctrl Key to Page Up Key.
 *__3.3 Inner Right Button changed from Back Key to Page Down Key.
 *__3.4 Outer Right Button changed from Left Shift Key to Menu Key.
 *__3.5 Center Key of 5-way Button changed from Enter Key to Home Key.
 */


#define NUM_KEYCODES	256

static unsigned short keycodes[NUM_KEYCODES] = {

	/*
	 *[0x01] = KEY_UP,
	 *[0x02] = KEY_DOWN,
	 *[0x03] = KEY_LEFT,
	 *[0x04] = KEY_RIGHT,
	 */
#if (BBQ20KBD_TRACKPAD_USE == BBQ20KBD_TRACKPAD_AS_MOUSE)
	[0x05] = BTN_LEFT,
#elif (BBQ20KBD_TRACKPAD_USE == BBQ20KBD_TRACKPAD_AS_KEYS)
	[0x05] = KEY_ENTER,
#endif

	[0x06] = KEY_SEND,
	[0x11] = 580,
	[0x07] = KEY_BACK,
	[0x12] = KEY_HOMEPAGE,

	[0x1A] = KEY_LEFTALT,
	[0x1B] = KEY_LEFTSHIFT,
	[0x1D] = KEY_RIGHTALT,
	[0x1C] = KEY_RIGHTSHIFT,

	['A'] = KEY_A,
	['B'] = KEY_B,
	['C'] = KEY_C,
	['D'] = KEY_D,
	['E'] = KEY_E,
	['F'] = KEY_F,
	['G'] = KEY_G,
	['H'] = KEY_H,
	['I'] = KEY_I,
	['J'] = KEY_J,
	['K'] = KEY_K,
	['L'] = KEY_L,
	['M'] = KEY_M,
	['N'] = KEY_N,
	['O'] = KEY_O,
	['P'] = KEY_P,
	['Q'] = KEY_Q,
	['R'] = KEY_R,
	['S'] = KEY_S,
	['T'] = KEY_T,
	['U'] = KEY_U,
	['V'] = KEY_V,
	['W'] = KEY_W,
	['X'] = KEY_X,
	['Y'] = KEY_Y,
	['Z'] = KEY_Z,

	[' '] = KEY_SPACE,
	['~'] = KEY_0,
	['$'] = KEY_GRAVE,

	['\b'] = KEY_BACKSPACE,
	['\n'] = KEY_ENTER,
	/*
	 * As per the kernel, a keyboard needs to indicate, in advance, which key values it can report.
	 * In order to that, it should have unique scancodes pointing those scancode-keycode pairs.
	 * With the configuration set for now, the keyboard never outputs lower case letters, numbers, and equal to sign.
	 * We can use these as bogus scancodes, and map the keys we want the keyboard to say its pressed when modifier keys are used.
	 * This can change however, in case future software versions of the keyboard micrcontroller itself changes to output other stuff.
	 */
	['1'] = KEY_1,
	['2'] = KEY_2,
	['3'] = KEY_3,
	['4'] = KEY_4,
	['5'] = KEY_5,
	['6'] = KEY_6,
	['7'] = KEY_7,
	['8'] = KEY_8,
	['9'] = KEY_9,
	['a'] = KEY_VOLUMEDOWN,
	['b'] = KEY_VOLUMEUP,
	['c'] = KEY_MUTE,
	['d'] = KEY_TAB,
	['e'] = KEY_DELETE,
	['f'] = KEY_ESC,
	['='] = KEY_EQUAL,
	['g'] = BTN_LEFT,
	['h'] = BTN_RIGHT,
	['i'] = KEY_UP,
	['j'] = KEY_DOWN,
	['k'] = KEY_LEFT,
	['l'] = KEY_RIGHT,
	['m'] = KEY_HOME,
};


#endif
