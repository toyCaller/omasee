import QtQuick
import qs.Commons
import ".."
import "../../js/fmt.js" as F

Column {
  id: root
  property var host
  readonly property var mem: (host.stats && host.stats.mem) || ({})
  readonly property var parts: [
    { label: "Apps", value: mem.apps, color: "blue" }, { label: "Cache", value: mem.cache, color: "yellow" },
    { label: "Shared", value: mem.shared, color: "magenta" }, { label: "Free", value: mem.free, color: "green" }
  ]
  readonly property bool hasContent: !!mem.total
  spacing: Style.space(5)

  Head { theme: root.host.theme; title: "Memory"; value: F.bytes(root.mem.used) + " of " + F.bytes(root.mem.total) }
  Rectangle {
    width: parent.width
    height: Style.space(9)
    radius: height / 2
    clip: true
    color: root.host.theme.track
    Row {
      anchors.fill: parent
      Repeater {
        model: root.parts
        Rectangle {
          required property var modelData
          height: parent.height
          width: root.mem.total ? root.width * Math.max(0, modelData.value || 0) / root.mem.total : 0
          color: root.host.theme.color(modelData.color)
          Behavior on width { enabled: root.host.theme.animate; NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        }
      }
    }
  }
  Repeater {
    model: root.parts
    Pair {
      required property var modelData
      theme: root.host.theme
      dot: root.host.theme.color(modelData.color)
      label: modelData.label
      value: F.bytes(modelData.value)
    }
  }
  Pair {
    visible: !!root.mem.swapTotal
    theme: root.host.theme
    label: "Swap"
    value: F.bytes(root.mem.swapUsed) + " of " + F.bytes(root.mem.swapTotal)
    showMeter: true
    meter: root.mem.swapTotal ? 100 * root.mem.swapUsed / root.mem.swapTotal : 0
    meterColor: root.host.theme.color("cyan")
  }
}
