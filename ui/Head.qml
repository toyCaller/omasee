import QtQuick
import qs.Commons

// Card title on the left, live value on the right.
Item {
  id: root
  property var theme
  property string title
  property string value
  width: parent ? parent.width : 0
  implicitHeight: t.implicitHeight

  Txt {
    id: t
    theme: root.theme
    text: root.title
    font.pixelSize: Style.font.body
    font.weight: Font.DemiBold
    anchors.left: parent.left
    anchors.right: v.left
    anchors.rightMargin: Style.space(8)
  }
  Txt {
    id: v
    theme: root.theme
    text: root.value
    anchors.right: parent.right
    anchors.baseline: t.baseline
    font.features: { "tnum": 1 }
  }
}
