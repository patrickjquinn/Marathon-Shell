import QtQuick
import QtTest
import MarathonUI.Core

TestCase {
    name: "MDateTimePicker"
    when: windowShown

    Component {
        id: pickerComponent
        MDateTimePicker {}
    }

    function test_tumblerDelegatesCreateWithoutErrors() {
        failOnWarning(/visibleItemCount/);
        const picker = createTemporaryObject(pickerComponent, this);
        verify(picker);
        wait(50);
    }
}
