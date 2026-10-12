# Template App

The starting point for a new Marathon app: a minimal Keel (Sailfish Silica) app with a page,
a pulley menu, a list with a context menu, persisted state, a cover and tests. It is not in
`apps/CMakeLists.txt`, so it is never built or shipped itself.

## Start a new app

1. `cp -r apps/template apps/myapp`
2. `manifest.json`: set `id`, `name`, `description`, `permissions`; add `assets/icon.svg`.
3. Rename `TemplateApp.qml` (and the `entryPoint`), set `appId`, and change the
   `/apps/template/...` configuration keys.
4. `CMakeLists.txt`: set `APP_NAME` and the `MarathonApp.<Name>` URI.
5. Add `add_subdirectory(myapp)` to `apps/CMakeLists.txt`.

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

See docs/superpowers/KEEL_APP_MIGRATION.md for the full rules and the verification steps.
