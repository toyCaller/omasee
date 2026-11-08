import QtQuick
import qs.Commons
import ".."
import "../../js/fmt.js" as F

Column {
  id: root
  property var host
  readonly property string metric: host.spec.metric
  readonly property int count: ({ s: 3, m: 5, l: 10 })[host.spec.size] || 5
  readonly property var table: (host.stats && host.stats.processes && host.stats.processes[metric]) || []
  // Idle processes all read zero disk; listing them in arbitrary order says nothing.
  readonly property var shown: table.filter(function(r) { return metric !== "disk" || r.io > 0 }).slice(0, count)
  readonly property string field: metric === "disk" ? "io" : metric
  readonly property real peak: Math.max.apply(null, [1e-9].concat(shown.map(function(r) { return r[field] || 0 })))
  readonly property color tint: host.theme.color(metric === "cpu" ? "blue" : metric === "memory" ? "magenta" : "orange")
  spacing: Style.space(3)

  function valueFor(r) {
    if (metric === "cpu") return (r.cpu < 10 ? r.cpu.toFixed(1) : Math.round(r.cpu)) + "%"
    if (metric === "memory") return F.bytes(r.memory)
    return "R " + F.rate(r.read) + "  W " + F.rate(r.write)
  }

  Head { theme: root.host.theme; title: "Top processes"; value: ({ cpu: "by CPU", memory: "by memory", disk: "by disk" })[root.metric] }
  Repeater {
    model: root.shown
    Item {
      required property var modelData
      required property int index
      width: root.width
      height: Style.space(21)
      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height - Style.space(3)
        width: Math.max(radius * 2, parent.width * (modelData[root.field] || 0) / root.peak)
        radius: Style.space(4)
        color: root.host.theme.alpha(root.tint, 0.16 - index * 0.012)
        Behavior on width { enabled: root.host.theme.animate; NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
      }
      Txt {
        theme: root.host.theme
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.right: v.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.name + (modelData.count > 1 ? "  ×" + modelData.count : "")
      }
      Txt {
        id: v
        theme: root.host.theme
        anchors.right: parent.right
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: root.valueFor(modelData)
        font.features: { "tnum": 1 }
      }
    }
  }
  Txt {
    visible: root.shown.length === 0
    theme: root.host.theme
    dim: true
    height: Style.space(21)
    text: root.metric === "disk" ? "Disks are quiet" : "Gathering…"
  }
  // Keeps the card height steady while the first detailed sample arrives.
  Item { width: 1; height: Math.max(0, root.count - Math.max(1, root.shown.length)) * Style.space(24) }
}
