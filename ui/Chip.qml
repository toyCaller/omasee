import QtQuick
import qs.Commons

// Small pill button used by the report header and the layout editor.
Rectangle {
  id: root
  property var theme
  property string text
  property bool emphasis: false
  signal clicked()

  implicitWidth: label.implicitWidth + Style.space(14)
  implicitHeight: label.implicitHeight + Style.space(7)
  radius: height / 2
  color: emphasis ? theme.alpha(theme.accent, mouse.containsMouse ? 0.32 : 0.2)
                  : mouse.containsMouse ? theme.track : theme.card
  border.width: 1
  border.color: emphasis ? theme.alpha(theme.accent, 0.55) : theme.edge
  scale: mouse.pressed ? 0.94 : 1

  Behavior on color { enabled: root.theme.animate; ColorAnimation { duration: 140 } }
  Behavior on scale { enabled: root.theme.animate; NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

  Txt {
    id: label
    theme: root.theme
    text: root.text
    anchors.centerIn: parent
    font.weight: root.emphasis ? Font.DemiBold : Font.Normal
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
