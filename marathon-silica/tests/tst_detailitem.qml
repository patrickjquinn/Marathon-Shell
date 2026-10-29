import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "DetailItem"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component {
        id: detail
        DetailItem {
            label: "Battery"
            value: "99%"
        }
    }

    function test_labelAndValueStartFromTheLeft() {
        const d = createTemporaryObject(detail, testCase);
        compare(d.alignment, Qt.AlignLeft);
        verify(d._valueItem.x < d.width / 2, "the value follows the label, not the centre line");
        compare(d._valueItem.horizontalAlignment, Text.AlignLeft);
    }
}
