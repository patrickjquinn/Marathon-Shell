.pragma library

// Per unit of Theme.pixelRatio. At 254 dpi (ratio 0.79) a 1600 px/s fling
// glides about 0.6 s and 500 px, as Android's OverScroller does on the same
// device; 16000 is Android's 8000 dp/s cap.
const deceleration = 3500;
const maxVelocity = 16000;
// Android's tap timeout: a press shows only once it hasn't become a scroll.
const tapTimeout = 100;
// A press this soon after a fling ends only stops it (FlingStopper).
const flingTapGuard = 50;
// Pacific's fling carry: a fling caught and flung again the same way adds
// the caught speed when it was at least 350 CSS px/s (700 per unit of
// pixelRatio), the new one at least half of it, and the finger rested no
// more than 100 ms; 36000 is its 18000 CSS px/s cap. A finger that rests
// 40 ms before lifting doesn't fling.
const carryFloor = 700;
const carryMin = 0.5;
const carryPauseMs = 100;
const carryMaxVelocity = 36000;
const pauseMs = 40;
