import QtQuick
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc
    name: "NotificationToastReply"
    when: windowShown
    width: 540
    height: 1140
    visible: true

    NotificationToast {
        id: toast
        width: 540
        height: 1140
    }

    function text(id) {
        return {
            "id": id,
            "appId": "messages",
            "title": "Alice",
            "body": "msg " + id,
            "replyTarget": "+15551234567",
            "actions": [
                {
                    "key": "inline-reply",
                    "label": "Reply"
                }
            ]
        };
    }

    function test_replySurvivesANewerTextInTheThread() {
        toast.showToast(text(1));
        toast.openReply();
        const field = findChild(toast, "replyField");
        field.text = "On my wa";
        NotificationService.notificationDismissed(1);
        toast.showToast(text(2));
        compare(toast.currentToast.id, 2);
        verify(toast.showInlineReply);
        compare(field.text, "On my wa");
        toast.sendReply();
        compare(NotificationService.replies, ["2:On my wa"]);
    }
}
