# Sailfish UX: what Marathon keeps, what it drops

Source: a pass over forum.sailfishos.org (2023–2026), October 2026. The evidence is thin to moderate: 6 threads were read in full and the rest came from search results. Threads are listed at the end.

Marathon's navigation does not change. The bottom pill is the one gesture surface:
- left → back
- up → home or the switcher
- right → forward
- down → quick settings

Sailfish's look sits on top of that navigation model.

## Keep
- **Eyes-free, one-handed operation.** Users praise this the most. Every system action stays in the bottom half of the screen.
- **Menus in a predictable place.** The pulley stays, but only for a few page-wide actions.
- **Covers in the switcher**, with large cover actions. Small ones get tapped by accident.
- **The visual language:** ambiences, highlight colour, typography, and the restraint of the overall look.

## Drop or modernise
- **Invisible edge swipes.** Users find them undiscoverable, they break under screen protectors, and the top corners are out of reach on tall phones. The pill is the visible affordance, so add no new edge gestures.
- **Pulley as the only route to actions.** It's hidden in the middle of a list. Per-item actions go in long-press context menus, and anything that depends on scroll position stays out of the pulley.
- **Top menu with dead controls**, such as the lock button nobody uses. Marathon's shade has user-configurable toggles and no dead controls.
- **Exit paths that depend on how you entered** (the Events view and the lock screen). In Marathon, back always returns to the previous state.
- **No privacy or permission signals.** Show camera, mic and location indicators, and give each app real permissions.
- **Flat, dated surfaces.** Marathon's version adds depth and tactile feedback.

## Consistency rules
- **One type scale and one density for the shell and every app.** Users report that font sizes are "all over the place" on a single page. The shell owns scale and pushes it to every toolkit: Silica `theme_pixel_ratio`, Qt, GTK, WebKit, Android.
- **Toolkit-independent navigation.** Apps that aren't Silica still get the pill, back and the shade. Nothing requires an app to have a pulley menu.
- **One store and one permission model.**

## Threads
- https://forum.sailfishos.org/t/first-impressions/17397
- https://forum.sailfishos.org/t/solving-the-issue-with-pulldown-up-menus/9315
- https://forum.sailfishos.org/t/sailfish-is-stagnant-some-improvements-that-are-neeed-imo/26861
- https://forum.sailfishos.org/t/android-enshittification-process-lets-promote-sailfish-os/24976?page=3
- https://forum.sailfishos.org/t/some-android-app-icons-are-low-res-once-sailfishified/20851
