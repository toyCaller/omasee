import QtQuick
import qs.Commons
import ".."

Column {
  id: root
  property var host
  readonly property var list: (host.stats && host.stats.net && host.stats.net.interfaces) || []
  readonly property bool hasContent: list.length > 0
  spacing: Style.space(4)

  Head { theme: root.host.theme; title: "Interfaces" }
  Repeater {
    model: root.list
    Pair {
      required property var modelData
      theme: root.host.theme
      dot: root.host.theme.color("green")
      label: modelData.name + "  ·  " + (modelData.kind === "wifi" ? "Wi-Fi" : "Ethernet") + (modelData.speed ? "  ·  " + modelData.speed + " Mb/s" : "")
      value: modelData.ip || "No address"
    }
  }
}
