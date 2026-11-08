import QtQuick
import qs.Commons
import qs.Ui

// One bar section (CPU / GPU / NET): a breathing heartbeat dot, the live text, and a
// faint sparkline of the last minute or so running underneath.
WidgetButton {
  id: root
  property var theme
  property bool highlighted: false
  property real load: 0               // 0–100, drives dot color and breathing speed
  property bool stale: false
  property var spark: []
  property real sparkCeiling: 100
  property bool showSpark: true
  property bool showDot: true
  property int seq: 0
  readonly property bool animate: !!theme && theme.animate
  readonly property color tone: stale || !theme ? (theme ? theme.faint : "gray") : theme.color(load >= 85 ? "red" : load >= 60 ? "yellow" : "green")

  horizontalMargin: 7
  active: !stale && load >= 85
  dimmed: stale

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: Style.space(3)
    anchors.bottomMargin: Style.space(3)
    z: -2
    radius: Style.space(6)
    color: root.foreground
    opacity: root.highlighted ? 0.13 : root.tooltipHovered ? 0.06 : 0
    Behavior on opacity { NumberAnimation { duration: 160 } }
  }

  Spark {
    visible: root.showSpark && !root.vertical
    z: -1
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: Style.space(4)
    anchors.rightMargin: Style.space(4)
    anchors.bottomMargin: Style.space(4)
    height: parent.height * 0.5
    values: root.spark
    ceiling: root.sparkCeiling
    tint: root.tone
  }

  Item {
    visible: root.showDot && !root.vertical
    width: Style.space(6)
    height: width
    anchors.left: parent.left
    anchors.leftMargin: Style.space(5)
    anchors.verticalCenter: parent.verticalCenter

    Rectangle {
      id: ring
      anchors.centerIn: parent
      width: parent.width; height: width; radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: root.tone
      opacity: 0
    }
    Rectangle {
      id: dot
      anchors.centerIn: parent
      width: parent.width; height: width; radius: width / 2
      color: root.tone
      Behavior on color { ColorAnimation { duration: 400 } }
      // Breathes faster as the load climbs.
      SequentialAnimation on opacity {
        id: breath
        running: root.animate && !root.stale && root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: Math.max(260, 1500 - root.load * 12); easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: Math.max(260, 1500 - root.load * 12); easing.type: Easing.InOutSine }
      }
    }
    ParallelAnimation {
      id: beat
      NumberAnimation { target: ring; property: "scale"; from: 1; to: 2.6; duration: 700; easing.type: Easing.OutCubic }
      NumberAnimation { target: ring; property: "opacity"; from: 0.8; to: 0; duration: 700; easing.type: Easing.OutCubic }
    }
  }

  onSeqChanged: if (animate && !stale && showDot) beat.restart()
}
