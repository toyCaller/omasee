import QtQuick
import qs.Commons
import ".."
import "../../js/signals.js" as S
import "../../js/fmt.js" as F

Column {
  id: root
  property var host
  readonly property var stats: host.stats || ({})
  readonly property var cpu: stats.cpu || ({})
  readonly property var gpu: (stats.gpu && stats.gpu[0]) || ({})
  readonly property var mem: stats.mem || ({})
  readonly property bool f: host.fahrenheit
  readonly property string metric: host.spec.metric
  spacing: Style.space(9)

  function has(v) { return !F.missing(v) }

  readonly property var dials: {
    var out = []
    if (metric === "gpu") {
      out.push({ label: "Load", value: gpu.usage, text: F.percent(gpu.usage) })
      if (has(gpu.memPct)) out.push({ label: "VRAM", value: gpu.memPct, text: F.percent(gpu.memPct) })
      if (has(gpu.temp)) out.push({ label: "Temp", value: gpu.temp, text: F.temp(gpu.temp, f) })
      if (has(gpu.clock)) out.push({ label: "Clock", value: gpu.clockMax ? 100 * gpu.clock / gpu.clockMax : 0,
                                     text: (gpu.clock / 1000).toFixed(1) + "G", color: "blue" })
    } else if (metric === "mem") {
      out.push({ label: "Memory", value: mem.usedPct, text: F.percent(mem.usedPct) })
      if (mem.swapTotal) out.push({ label: "Swap", value: 100 * mem.swapUsed / mem.swapTotal, text: F.percent(100 * mem.swapUsed / mem.swapTotal) })
      if (has(mem.pressure)) out.push({ label: "Pressure", value: mem.pressure, text: F.percent(mem.pressure) })
    } else {
      out.push({ label: "Load", value: cpu.usage, text: F.percent(cpu.usage) })
      if (has(cpu.temp)) out.push({ label: "Temp", value: cpu.temp, text: F.temp(cpu.temp, f) })
      if (has(cpu.power)) out.push({ label: "Power", value: cpu.power / 2.5, text: F.watts(cpu.power), color: "yellow" })
      if (has(cpu.freq)) out.push({ label: "Clock", value: Math.min(100, cpu.freq / 50), text: (cpu.freq / 1000).toFixed(1) + "G", color: "blue" })
    }
    return out
  }

  Head {
    visible: root.metric === "gpu"
    theme: root.host.theme
    title: root.gpu.name || "GPU"
    value: root.has(root.gpu.power) ? F.watts(root.gpu.power) + (root.gpu.powerLimit ? " of " + root.gpu.powerLimit + "W" : "")
         : root.gpu.asleep ? "Asleep" : ""
  }
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.space(14)
    Repeater {
      model: root.dials
      Dial {
        required property var modelData
        theme: root.host.theme
        label: modelData.label
        text: modelData.text
        value: F.missing(modelData.value) ? 0 : modelData.value
        fill: root.host.theme.color(modelData.color || S.level(modelData.value))
      }
    }
  }
  Txt {
    visible: text !== ""
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    theme: root.host.theme
    dim: true
    font.pixelSize: Style.font.caption
    text: {
      if (root.metric === "cpu") return root.cpu.model || ""
      if (root.metric === "mem") return root.has(root.mem.total) ? F.bytes(root.mem.used) + " of " + F.bytes(root.mem.total) + " in use" : ""
      var g = root.gpu, parts = []
      if (root.has(g.memUsed) && g.memTotal) parts.push("VRAM " + F.bytes(g.memUsed) + " of " + F.bytes(g.memTotal))
      if (root.has(g.fan)) parts.push("Fan " + F.percent(g.fan))
      if (root.has(g.pstate)) parts.push("P" + g.pstate)
      if (root.has(g.clockMax)) parts.push("max " + F.clock(g.clockMax))
      return parts.join("  ·  ")
    }
  }
}
