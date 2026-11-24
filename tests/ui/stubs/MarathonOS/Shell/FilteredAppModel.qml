import QtQuick

ListModel {
    property int pageSize: 0
    property int pageIndex: 0
    property bool pinnedMode: true

    // A test appends {id, name, icon} rows for the grid to show.
    function getAppAtIndex(index) {
        return index >= 0 && index < count ? get(index) : null;
    }
}
