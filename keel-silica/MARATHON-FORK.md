# Marathon's fork of Keel

This directory is Marathon's own copy of Keel, `keel/` in Shipwright
(published as `shipwright-open`). Marathon changes it freely; Shipwright
keeps its own copy for its Sailfish OS apps.

## Base

- `shipwright-open` commit `0df499bf34e02cec7f571853cbf5a4323dc1609e`,
  "Export of 7a6c40a883d1", the commit `packaging/packages/keel-silica`
  builds.
- Imported with its history: `keel/` was split out of `shipwright-open` at
  that commit (tip `2b87e66e772ef0ffc7c0872a5d01162eb4ec0ed8`) and merged
  in here as a subtree.

## Reconciling with Shipwright

- What Marathon changed: `git diff 2b87e66e772e HEAD -- keel-silica/`.
- Taking a newer Shipwright export: split `keel/` out of it the same way,
  then `git merge -X subtree=keel-silica/ <split tip>`, and update the base
  above.
- Marathon's changes are separate commits that touch only this directory,
  so they can be carried back one by one.

## Licences

Unchanged from Shipwright:
- Keel is MIT.
- The ported Silica QML and keel-shell's upstream parts are BSD-3-Clause.
- The Nemo compatibility libraries are LGPL-2.1-only and stay separate
  shared libraries.

See `LICENSE` and the `PROVENANCE.md` files.
