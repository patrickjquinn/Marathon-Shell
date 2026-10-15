import QtQuick
import Sailfish.Silica as S

S.DialogHeader {
    id: root

    objectName: "dialogHeader"
    Accessible.role: Accessible.Heading
    Accessible.name: title

    DialogHeaderBackdrop {
        header: root
    }
}
