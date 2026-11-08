.pragma library
.import "fmt.js" as F

// Every graphable signal. Colors are palette roles resolved by ui/Palette.qml.
var info = {
  "cpu.load": { title: "CPU load", kind: "percent", stacked: true, series: [
    { key: "cpuUser", label: "User", color: "blue" }, { key: "cpuSystem", label: "System", color: "red" }] },
  "cpu.temp": { title: "CPU temperature", kind: "temp", series: [{ key: "cpuTemp", label: "Temp", color: "orange" }] },
  "cpu.power": { title: "CPU power", kind: "watts", series: [{ key: "cpuPower", label: "Power", color: "yellow" }] },
  "gpu.usage": { title: "GPU load", kind: "percent", series: [{ key: "gpuUsage", label: "Load", color: "green" }] },
  "gpu.memory": { title: "GPU memory", kind: "percent", series: [{ key: "gpuMemory", label: "Memory", color: "magenta" }] },
  "gpu.temp": { title: "GPU temperature", kind: "temp", series: [{ key: "gpuTemp", label: "Temp", color: "orange" }] },
  "gpu.power": { title: "GPU power", kind: "watts", series: [{ key: "gpuPower", label: "Power", color: "yellow" }] },
  "net": { title: "Network", kind: "rate", mirrored: true, series: [
    { key: "netDown", label: "Down", color: "cyan" }, { key: "netUp", label: "Up", color: "magenta" }] },
  "disk": { title: "Disk activity", kind: "rate", mirrored: true, series: [
    { key: "diskRead", label: "Read", color: "blue" }, { key: "diskWrite", label: "Write", color: "orange" }] },
  "mem.used": { title: "Memory used", kind: "percent", series: [{ key: "memUsed", label: "Used", color: "magenta" }] },
  "mem.pressure": { title: "Memory pressure", kind: "percent", series: [{ key: "memPressure", label: "Pressure", color: "orange" }] },
  "swap": { title: "Swap used", kind: "percent", series: [{ key: "swapUsed", label: "Swap", color: "cyan" }] }
}

function current(stats, key, fahrenheit) {
  var s = stats || {}, cpu = s.cpu || {}, gpu = (s.gpu && s.gpu[0]) || {}, net = s.net || {}, disks = s.disks || {}, mem = s.mem || {}
  switch (key) {
  case "cpu.load": return F.percent(cpu.usage)
  case "cpu.temp": return F.temp(cpu.temp, fahrenheit)
  case "cpu.power": return F.watts(cpu.power)
  case "gpu.usage": return F.percent(gpu.usage)
  case "gpu.memory": return F.percent(gpu.memPct)
  case "gpu.temp": return F.temp(gpu.temp, fahrenheit)
  case "gpu.power": return F.watts(gpu.power)
  case "net": return "↓ " + F.rate(net.down) + "  ↑ " + F.rate(net.up)
  case "disk": return "R " + F.rate(disks.read) + "  W " + F.rate(disks.write)
  case "mem.used": return F.percent(mem.usedPct)
  case "mem.pressure": return F.percent(mem.pressure)
  case "swap": return F.percent(mem.swapTotal ? 100 * mem.swapUsed / mem.swapTotal : null)
  }
  return F.NONE
}

function caption(stats, key, fahrenheit) {
  var s = stats || {}
  if (key === "cpu.load") {
    var c = s.cpu || {}
    var bits = [F.clock(c.freq)]
    if (!F.missing(c.temp)) bits.push(F.temp(c.temp, fahrenheit))
    if (!F.missing(c.power)) bits.push(F.watts(c.power))
    return bits.join(" · ")
  }
  if (key === "gpu.usage") {
    var g = (s.gpu && s.gpu[0]) || {}
    var gb = []
    if (!F.missing(g.clock)) gb.push(F.clock(g.clock))
    if (!F.missing(g.power)) gb.push(F.watts(g.power))
    if (!F.missing(g.temp)) gb.push(F.temp(g.temp, fahrenheit))
    return gb.join(" · ")
  }
  return ""
}

function range(kind, lists) {
  if (kind === "percent") return { min: 0, max: 100 }
  var peak = 0
  ;(lists || []).forEach(function(vals) { (vals || []).forEach(function(v) { if (v !== null && v > peak) peak = v }) })
  if (kind === "temp") return { min: 20, max: Math.max(70, Math.min(105, peak + 5), peak) }
  // A little headroom so the line never scrapes the top edge.
  return { min: 0, max: peak > 0 ? peak * 1.12 : 1 }
}

// Palette role for a 0–100 reading.
function level(v) {
  if (v === null || v === undefined || isNaN(v)) return "muted"
  if (v >= 85) return "red"
  if (v >= 60) return "yellow"
  return "green"
}

function hot(v) { return v !== null && v !== undefined && v >= 85 }
