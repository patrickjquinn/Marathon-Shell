# Marathon OS design bundle

An exported HTML/CSS/JS mockup bundle: the source of truth for the
next-generation surfaces, used as the visual reference when implementing
them for real.

## How to use it

**Read `marathonos/project/Marathon OS.html` in full** -- it is the primary
design. Then follow its imports: shared components, CSS and scripts, so the
pieces are understood together before implementing.

Confirm anything ambiguous before building -- clarifying scope up front is
cheaper than building the wrong thing.

## About the design files

The design medium is **HTML/CSS/JS** — these are prototypes, not production code. Your job is to **recreate them pixel-perfectly** in whatever technology makes sense for the target codebase (React, Vue, native, whatever fits). Match the visual output; don't copy the prototype's internal structure unless it happens to fit.

**Don't render these files in a browser or take screenshots unless the user asks you to.** Everything you need — dimensions, colors, layout rules — is spelled out in the source. Read the HTML and CSS directly; a screenshot won't tell you anything they don't.

## Bundle contents

- `marathonos/README.md` — this file
- `marathonos/project/` — the `MarathonOS` project files (HTML prototypes, assets, components)
