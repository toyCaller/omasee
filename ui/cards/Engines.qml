import QtQuick
import qs.Commons
import ".."
import "../../js/fmt.js" as F

Column {
  id: root
  property var host
  readonly property var engines: (host.stats && host.stats.gpu && host.stats.gpu[0] && host.stats.gpu[0].engines) || ({})
  readonly property var rows: [
    { key: "graphics", label: "3D and compute", color: "green" }, { key: "encode", label: "Video encode", color: "blue" },
    { key: "decode", label: "Video decode", color: "cyan" }, { key: "jpeg", label: "JPEG", color: "magenta" },
    { key: "opticalFlow", label: "Optical flow", color: "yellow" }
  ].filter(function(r) { return !F.missing(root.engines[r.key]) })
  readonly property bool hasContent: rows.length > 0
  spacing: Style.space(5)

  Head { theme: root.host.theme; title: "Engines" }
  Repeater {
    model: root.rows
    Pair {
      required property var modelData
      theme: root.host.theme
      label: modelData.label
      value: F.percent(root.engines[modelData.key])
      showMeter: true
      meter: root.engines[modelData.key] || 0
      meterColor: root.host.theme.color(modelData.color)
    }
  }
}
