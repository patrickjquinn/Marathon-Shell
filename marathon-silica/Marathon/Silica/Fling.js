.pragma library

// Per unit of Theme.pixelRatio. At 254 dpi (ratio 0.79) a fling stops within
// 15% of where Android's OverScroller stops it from 2000-6000 px/s; 16000 is
// Android's 8000 dp/s cap.
const deceleration = 6300;
const maxVelocity = 16000;
