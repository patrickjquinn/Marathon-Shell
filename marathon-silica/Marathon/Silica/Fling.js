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
