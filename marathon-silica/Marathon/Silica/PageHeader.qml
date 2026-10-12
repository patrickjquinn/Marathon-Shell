import QtQuick
import Sailfish.Silica as S

S.PageHeader {
    objectName: "pageHeader"
    Accessible.role: Accessible.Heading
    Accessible.name: title
    Accessible.description: description
}
