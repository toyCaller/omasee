import QtQuick
import qs.Commons

// One label/value row, with an optional level meter underneath.
Column {
  id: root
  property var theme
  property string label
  property string value
  property bool showMeter: false
  property real meter: 0
  property color meterColor: theme ? theme.foreground : "white"
  property color dot: "transparent"
  width: parent ? parent.width : 0
  spacing: Style.space(3)

  Item {
    width: parent.width
    implicitHeight: name.implicitHeight
    Rectangle {
      id: swatch
      visible: root.dot.a > 0
      width: visible ? Style.space(7) : 0
      height: width
      radius: width / 2
      color: root.dot
      anchors.verticalCenter: parent.verticalCenter
    }
    Txt {
      id: name
      theme: root.theme
      dim: true
      text: root.label
      anchors.left: swatch.right
      anchors.leftMargin: swatch.visible ? Style.space(6) : 0
      anchors.right: val.left
      anchors.rightMargin: Style.space(8)
    }
    Txt {
      id: val
      theme: root.theme
      text: root.value
      anchors.right: parent.right
      font.features: { "tnum": 1 }
    }
  }
  Meter {
    visible: root.showMeter
    width: parent.width
    theme: root.theme
    value: root.meter
    fill: root.meterColor
  }
}
