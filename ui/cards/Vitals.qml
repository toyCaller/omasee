import QtQuick
import qs.Commons
import ".."
import "../../js/fmt.js" as F

Column {
  id: root
  property var host
  readonly property var cpu: (host.stats && host.stats.cpu) || ({})
  readonly property var load: cpu.load || []
  readonly property var procs: (host.stats && host.stats.processes) || ({})
  spacing: Style.space(4)

  Pair {
    theme: root.host.theme
    label: "Load average  1 · 5 · 15 min"
    value: root.load.length ? root.load.map(function(v) { return v.toFixed(2) }).join("  ") : F.NONE
  }
  Pair { theme: root.host.theme; label: "Clock"; value: F.clock(root.cpu.freq) }
  Pair { theme: root.host.theme; label: "Processes"; value: root.procs.total ? String(root.procs.total) : F.NONE }
  Pair { theme: root.host.theme; label: "Uptime"; value: F.duration(root.cpu.uptime) }
}
