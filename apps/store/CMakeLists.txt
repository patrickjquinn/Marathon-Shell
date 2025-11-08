# The add_marathon_app function is already available from parent CMakeLists

set(QML_FILES
    StoreApp.qml
    pages/StoreFrontPage.qml
    pages/AppDetailPage.qml
    pages/InstalledAppsPage.qml
    pages/UpdatesPage.qml
    components/FeaturedAppCard.qml
    components/AppListItem.qml
    components/InfoRow.qml
    qmldir
)

set(RESOURCES
    manifest.json
    assets/icon.svg
)

add_marathon_app(store "${QML_FILES}" "${RESOURCES}")

