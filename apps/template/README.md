# Template App

The starting point for a new Marathon app: a minimal Keel (Sailfish Silica) app with a page,
a pulley menu, a list with a context menu, persisted state, a cover and tests. It is not in
`apps/CMakeLists.txt`, so it is never built or shipped itself.

## Start a new app

```sh
scripts/new-app myapp "My App"
```

copies this directory to `apps/myapp`, renames the files, ids and settings keys, and adds it
to `apps/CMakeLists.txt`. Then fill in `manifest.json` (description, permissions), add an
icon, and try it on a development phone with `scripts/app-push myapp`.

docs/APP_DEVELOPMENT.md is the full guide.

## Layout

```
TemplateApp.qml        ApplicationWindow: appId, state, initialPage, cover
pages/MainPage.qml     Page: SilicaListView, PageHeader, PullDownMenu, ListItem + ContextMenu
cover/TemplateCover.qml
tests/                 qmltestrunner suite: KEEL_QML=... sh tests/run.sh
```

## Conventions

- Every QML file imports `Sailfish.Silica 1.0` then `Marathon.Silica 1.0`.
- Platform services come from `import Marathon.Platform 1.0`; app state from
  `Nemo.Configuration`, notifications from `Nemo.Notifications`, haptics from `Nemo.Ngf`.
- Theme sizes, colours and margins only; pulley menus for actions; remorse for deletes.

See docs/KEEL_APP_MIGRATION.md for the full rules and the verification steps.
