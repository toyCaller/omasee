import QtQuick
import qs.Commons
import ".."

Column {
  id: root
  property var host
  readonly property var list: (host.stats && host.stats.sensors && host.stats.sensors.fans) || []
  readonly property bool hasContent: list.length > 0
  spacing: Style.space(4)

  Head { theme: root.host.theme; title: "Fans" }
  Repeater {
    model: root.list
    Item {
      required property var modelData
      width: root.width
      implicitHeight: row.implicitHeight
      Pair { id: row; width: parent.width - Style.space(20); theme: root.host.theme; label: modelData.name.replace(/_/g, " "); value: modelData.rpm + " RPM" }
      // A little fan that spins in proportion to its RPM.
      Txt {
        anchors.right: parent.right
        anchors.verticalCenter: row.verticalCenter
        theme: root.host.theme
        text: "✻"
        color: root.host.theme.color(modelData.rpm > 0 ? "cyan" : "muted")
        RotationAnimation on rotation {
          running: root.host.theme.animate && modelData.rpm > 0 && root.visible
          loops: Animation.Infinite
          from: 0; to: 360
          duration: Math.max(250, 120000 / Math.max(1, modelData.rpm))
        }
      }
    }
  }
}
