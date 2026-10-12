import QtQuick
import QtTest
import Sailfish.Silica 1.0
import MarathonOS.Shell

TestCase {
    name: "Typography"

    function test_bodyMatchesSilica() {
        compare(MTypography.sizeBody, Theme.fontSizeMedium);
    }

    function test_hierarchyKept() {
        verify(MTypography.sizeFootnote < MTypography.sizeBody);
        verify(MTypography.sizeTitle1 > MTypography.sizeTitle3);
        compare(MTypography.sizeFootnote, Math.round(13 * Theme.fontSizeMedium / 17));
    }
}
