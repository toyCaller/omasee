import QtQuick
import qs.Commons

// A rounded level bar that glides to new values and breathes when the reading runs hot.
Rectangle {
  id: root
  property var theme
  property real value: 0
  property color fill: theme ? theme.foreground : "white"
  readonly property real clamped: Math.max(0, Math.min(100, isNaN(value) ? 0 : value))
  readonly property bool hot: clamped >= 85

  implicitHeight: Style.space(5)
  radius: height / 2
  color: theme ? theme.track : "gray"
  clip: true

  Rectangle {
    id: bar
    height: parent.height
    radius: parent.radius
    width: Math.max(clamped > 0 ? height : 0, root.width * root.clamped / 100)
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.darker(root.fill, 1.25) }
      GradientStop { position: 1; color: root.fill }
    }
    Behavior on width { enabled: !!root.theme && root.theme.animate; NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }

    SequentialAnimation on opacity {
      running: root.hot && !!root.theme && root.theme.animate && root.visible
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.55; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
    }
  }
}
