import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "FilePickerSheet"
    when: windowShown

    property var answers: []
    property int cancels: 0

    Window {
        id: win

        width: 540
        height: 1140
        visible: true

        FilePickerSheet {
            id: picker

            onAccepted: (paths, filterIndex, choices) => tc.answers.push({ "paths": paths, "filterIndex": filterIndex, "choices": choices })
            onCancelled: tc.cancels++
        }
    }

    function init() {
        answers = [];
        cancels = 0;
    }

    function cleanup() {
        picker.close();
    }

    function request(extra) {
        return Object.assign({ "mode": "open", "title": "", "multiple": false, "directory": false, "filters": [], "filterIndex": -1, "folder": "", "name": "", "files": [], "choices": [] }, extra);
    }

    function tapEntry(name) {
        let entry = null;
        tryVerify(() => (entry = findChild(picker, "fileEntry-" + name)) !== null && entry.visible);
        mouseClick(entry);
    }

    function test_aFileTapOpensIt() {
        picker.open(request({ "folder": "/home/u/Pictures" }));
        tapEntry("beach.png");
        compare(answers.length, 1);
        compare(answers[0].paths, ["/home/u/Pictures/beach.png"]);
        verify(!picker.shown);
    }

    function test_severalFilesOpenTogether() {
        picker.open(request({ "folder": "/home/u/Pictures", "multiple": true }));
        tapEntry("beach.png");
        tapEntry("notes.txt");
        const accept = findChild(picker, "filePickerAccept");
        compare(accept.text, "Open (2)");
        mouseClick(accept);
        compare(answers[0].paths, ["/home/u/Pictures/beach.png", "/home/u/Pictures/notes.txt"]);
    }

    function test_foldersOpenAndUpGoesBack() {
        picker.open(request({}));
        compare(findChild(picker, "filePickerFolder").text, "u");
        tapEntry("Documents");
        compare(findChild(picker, "filePickerFolder").text, "Documents");
        mouseClick(findChild(picker, "filePickerUp"));
        compare(findChild(picker, "filePickerFolder").text, "u");
    }

    function test_savingOverAFileAsksFirst() {
        picker.open(request({ "mode": "save", "folder": "/home/u/Documents", "name": "report.pdf" }));
        const accept = findChild(picker, "filePickerAccept");
        mouseClick(accept);
        compare(answers.length, 0);
        verify(findChild(picker, "filePickerReplace").visible);
        compare(accept.text, "Replace");
        mouseClick(accept);
        compare(answers[0].paths, ["/home/u/Documents/report.pdf"]);
    }

    function test_aFolderPickShowsFoldersAndAnswersTheFolder() {
        picker.open(request({ "directory": true, "folder": "/home/u/Documents" }));
        tapEntry("Old");
        verify(findChild(picker, "fileEntry-report.pdf") === null || !findChild(picker, "fileEntry-report.pdf").visible);
        mouseClick(findChild(picker, "filePickerAccept"));
        compare(answers[0].paths, ["/home/u/Documents/Old"]);
    }

    function test_cancelCancels() {
        picker.open(request({}));
        mouseClick(findChild(picker, "filePickerCancel"));
        compare(cancels, 1);
        verify(!picker.shown);
    }

    function test_picturesShowAsAGrid() {
        picker.open(request({ "filters": [{ "name": "Images", "globs": [], "mimes": ["image/*"] }], "filterIndex": 0 }));
        tryVerify(() => findChild(picker, "filePickerGrid") !== null);
        tapEntry("sea.png");
        compare(answers[0].paths, ["/home/u/Pictures/sea.png"]);
        compare(answers[0].filterIndex, 0);
    }

    function test_choicesComeBack() {
        picker.open(request({ "folder": "/home/u/Pictures", "multiple": true, "choices": [{ "id": "encoding", "label": "Encoding", "options": [{ "id": "utf8", "label": "UTF-8" }, { "id": "latin1", "label": "Latin-1" }], "value": "utf8" }] }));
        mouseClick(findChild(picker, "fileChoice-encoding-latin1"));
        tapEntry("beach.png");
        mouseClick(findChild(picker, "filePickerAccept"));
        compare(answers[0].choices.encoding, "latin1");
    }
}
