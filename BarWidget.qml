import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "ui"
import "js/prefs.js" as P
import "js/fmt.js" as F
import "js/deck.js" as D
import "js/pointer.js" as Ptr

BarWidget {
  id: root
  moduleName: "oladi.omasee"

  // ---------------------------------------------------------------- settings
  readonly property bool fahrenheit: setting("temperatureUnit", "Celsius") === "Fahrenheit"
  readonly property bool demo: setting("demo", false) === true
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string socketPath: runtimeDir === "" ? "" : runtimeDir + (demo ? "/omasee-demo.sock" : "/omasee.sock")
  readonly property string enginePath: decodeURIComponent(Qt.resolvedUrl("engine/omasee-engine").toString().replace(/^file:\/\//, ""))
  property var prefs: P.parse("")

  // ---------------------------------------------------------------- live data
  property var live: ({})
  property var detail: ({})
  property int seq: 0
  property double lastHeard: 0
  property bool stale: true

  readonly property int sparkLength: 48
  property var cpuSpark: []
  property var gpuSpark: []
  property var netSpark: []
  property real netPeak: 1

  // ---------------------------------------------------------------- reports and layouts
  property string activeReport: ""
  // Opened on purpose (click, keybinding, command): stays open until a click elsewhere.
  property bool pinned: false
  property var draft: null
  property var localLayouts: null
  readonly property bool editing: draft !== null
  readonly property var layouts: localLayouts || D.resolve(setting("layouts", null))

  property Palette theme: Palette {
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    animate: root.prefs.animations
  }

  readonly property string hoveredSection: cpuButton.tooltipHovered ? "cpu"
    : gpuButton.tooltipHovered ? "gpu" : netButton.tooltipHovered ? "system" : ""
  readonly property bool popupHovered: cpuSheet.containsMouse || gpuSheet.containsMouse || systemSheet.containsMouse

  // While a report is open the bar's hover state stops tracking the pointer, so the
  // pointer is read from Hyprland instead (and double-checked once before opening).
  property string polledSection: ""
  property bool confirmOpen: false
  property bool passExempt: false
  property var passTracker: null
  readonly property string pointerSection: activeReport !== "" ? polledSection : hoveredSection

  onPointerSectionChanged: Qt.callLater(updateHover)
  onPopupHoveredChanged: updateHover()
  onSettingsChanged: localLayouts = null
  onSocketPathChanged: { engine.running = false; link.connected = false }

  onActiveReportChanged: {
    passTracker = null
    passExempt = false
    if (activeReport === "") pinned = false
    syncDetail()
    if (activeReport !== "") {
      lastReport = activeReport
      theme.reload()
    }
  }

  function updateHover() {
    if (editing) return
    if (pinned) {
      if (pointerSection !== "" && pointerSection !== activeReport && !popupHovered) activeReport = pointerSection
      return
    }
    if (pointerSection !== "") {
      closeTimer.stop()
      if (activeReport === "") {
        prefsFile.reload()
        openTimer.restart()
      } else if (!popupHovered) activeReport = pointerSection
      return
    }
    openTimer.stop()
    confirmOpen = false
    if (popupHovered) closeTimer.stop()
    else if (activeReport !== "") closeTimer.restart()
  }

  function openReport(id) {
    if (D.REPORTS.indexOf(id) < 0) return
    closeTimer.stop()
    openTimer.stop()
    saveDraft()
    confirmOpen = false
    polledSection = hoveredSection
    activeReport = id
    pinned = true
    passExempt = true
  }

  function closeReport(id) {
    if (activeReport !== id || id === "") return
    saveDraft()
    activeReport = ""
  }

  function toggleReport(id) {
    if (activeReport === id) closeReport(id)
    else openReport(id)
  }

  // `omarchy-shell shell summon|hide|toggle` reach bar widgets through these.
  readonly property bool opened: activeReport !== ""
  property string lastReport: "cpu"
  function open() { openReport(lastReport) }
  function close() { closeReport(activeReport) }

  function beginEdit() {
    if (activeReport === "") return
    passExempt = true
    draft = D.copy(layouts[activeReport])
  }

  function saveDraft() {
    if (draft === null || activeReport === "") return
    var next = D.copy(layouts)
    next[activeReport] = draft
    draft = null
    localLayouts = next
    // argv, not a shell string: the JSON never passes through a shell.
    saver.command = ["omarchy", "bar", "set", moduleName, "layouts", JSON.stringify(D.overrides(next)), "--json"]
    saver.running = true
    updateHover()
  }

  function syncDetail() {
    if (!link.connected) return
    link.write(activeReport !== "" ? "detail on\n" : "detail off\n")
    link.flush()
  }

  function push(list, value) {
    var out = list.slice(Math.max(0, list.length - sparkLength + 1))
    out.push(typeof value === "number" && isFinite(value) ? value : 0)
    return out
  }

  function receive(line) {
    if (line.length > 8 * 1024 * 1024) return
    var m
    try { m = JSON.parse(line) } catch (e) { return }
    if (!m || typeof m !== "object" || !m.cpu || typeof m.cpu !== "object") return
    live = m
    if (m.detail) detail = m
    seq = typeof m.seq === "number" ? m.seq : seq + 1
    lastHeard = Date.now()
    stale = false
    cpuSpark = push(cpuSpark, m.cpu.usage)
    gpuSpark = push(gpuSpark, m.gpu && m.gpu[0] ? m.gpu[0].usage : 0)
    var net = m.net ? (m.net.down || 0) + (m.net.up || 0) : 0
    netSpark = push(netSpark, net)
    netPeak = Math.max(1024, Math.max.apply(null, netSpark))
  }

  readonly property bool onFocusedMonitor: {
    var w = root.QsWindow.window, f = Hyprland.focusedMonitor
    return !!w && !!w.screen && !!f && w.screen.name === f.name
  }

  function viaFocused(call) {
    var items = bar && bar.moduleWidgets ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) if (items[i] && items[i].onFocusedMonitor) call(items[i])
  }

  // IPC work runs on a short timer so the reply goes out before any report is built.
  property var pendingCall: null
  function later(call) { pendingCall = call; ipcDefer.restart() }
  Timer { id: ipcDefer; interval: 15; onTriggered: { var c = root.pendingCall; root.pendingCall = null; if (c) root.viaFocused(c) } }

  IpcHandler {
    target: "omasee"
    // Deferred so the IPC call returns at once; building a report can take longer
    // than omarchy-shell's 2 s IPC timeout on slower machines.
    function open(report: string): void { root.later(function(w) { w.openReport(report) }) }
    function toggle(report: string): void { root.later(function(w) { w.toggleReport(report) }) }
    function close(): void { root.later(function(w) { w.closeReport(w.activeReport) }) }
    function edit(): void { root.later(function(w) { w.beginEdit() }) }
  }

  // Optional, read-only, size-capped. Re-read whenever the pointer reaches the bar
  // because a file that doesn't exist yet can't be watched.
  FileView {
    id: prefsFile
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omasee/config.json"
    printErrors: false
    onLoaded: root.prefs = P.parse(text())
    onLoadFailed: root.prefs = P.parse("")
  }

  Timer {
    id: openTimer
    interval: root.pointerSection === "system" ? root.prefs.systemOpenDelayMs : root.prefs.openDelayMs
    onTriggered: { root.confirmOpen = true; pointerPoll.running = true }
  }
  Timer {
    id: closeTimer
    interval: root.prefs.closeDelayMs
    onTriggered: if (!root.editing && !root.popupHovered && root.pointerSection === "") root.activeReport = ""
  }

  function sectionRect(id, button) {
    var w = root.QsWindow.window, o = button.mapToItem(null, 0, 0)
    return { id: id, x: o.x + (w && w.screen ? w.screen.x : 0), y: o.y + (w && w.screen ? w.screen.y : 0),
             width: button.width, height: button.height }
  }

  function receivePointer(text) {
    var p = Ptr.parseCursor(text)
    if (!p) return
    var s = Ptr.sectionAt(p.x, p.y, [sectionRect("cpu", cpuButton), sectionRect("gpu", gpuButton), sectionRect("system", netButton)])
    if (confirmOpen) {
      confirmOpen = false
      if (s !== "" && activeReport === "") { polledSection = s; activeReport = s }
    } else if (activeReport !== "") {
      polledSection = s
      followPass(p, s)
    }
  }

  // Closes System when the pointer crosses it without stopping.
  function followPass(p, s) {
    if (activeReport !== "system" || passExempt || !prefs.closeOnPassThrough) return
    if (passTracker && passTracker.settled) return
    if (s !== "") passTracker = null
    else if (popupHovered) {
      passTracker = Ptr.trackPass(passTracker, p.x, p.y, Date.now(), prefs.passThroughMs)
      if (passTracker.through) activeReport = ""
    }
  }

  Process {
    id: pointerPoll
    command: ["hyprctl", "cursorpos", "-j"]
    stdout: StdioCollector { onStreamFinished: root.receivePointer(text) }
  }
  Timer {
    interval: 80
    repeat: true
    running: root.activeReport !== "" && !root.editing
    onTriggered: pointerPoll.running = true
  }

  Process {
    id: saver
    stderr: SplitParser { onRead: function(line) { console.warn("omasee: saving layout:", line) } }
  }

  // ---------------------------------------------------------------- engine
  // One engine serves every monitor. Each bar starts one only while disconnected;
  // a lock lets one win and the rest exit at once.
  Process {
    id: engine
    running: root.socketPath !== ""
    command: root.demo ? [root.enginePath, "--socket", root.socketPath, "--demo"] : [root.enginePath, "--socket", root.socketPath]
    stderr: SplitParser { onRead: function(line) { console.warn("omasee engine:", line) } }
  }
  Timer {
    interval: 2000
    repeat: true
    running: root.socketPath !== "" && !engine.running && !link.connected
    onTriggered: engine.running = true
  }

  Socket {
    id: link
    path: root.socketPath
    connected: root.socketPath !== ""
    onConnectedChanged: if (connected) root.syncDetail()
    parser: SplitParser { onRead: function(line) { root.receive(line) } }
  }
  Timer {
    interval: 2000
    repeat: true
    running: root.socketPath !== "" && !link.connected
    onTriggered: { link.connected = false; link.connected = true }
  }
  // Goes stale (dimmed, grey heartbeat) if the engine stops talking.
  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.stale = root.lastHeard === 0 || Date.now() - root.lastHeard > 6500
  }

  // ---------------------------------------------------------------- bar
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  readonly property var gpu0: live.gpu && live.gpu[0] ? live.gpu[0] : null
  readonly property real dotRoom: prefs.heartbeat ? Style.space(10) : 0

  TextMetrics { id: netWidth; font.family: theme.fontFamily; font.pixelSize: Style.font.body; text: "↓ 99.9 MB/s  ↑ 99.9 MB/s" }

  // Width follows what this machine reports, so a laptop without temperature or
  // power readings doesn't carry empty space, but doesn't jitter as digits change.
  TextMetrics {
    id: cpuMetrics; font.family: theme.fontFamily; font.pixelSize: Style.font.body
    text: F.section("CPU 100%", { temp: root.live.cpu ? root.live.cpu.temp : null, power: root.live.cpu ? root.live.cpu.power : null }, root.fahrenheit).replace(/\d+°/, "100°").replace(/\d+W/, "999W")
  }
  TextMetrics {
    id: gpuMetrics; font.family: theme.fontFamily; font.pixelSize: Style.font.body
    text: F.section("GPU 100%", { temp: root.gpu0 ? root.gpu0.temp : null, power: root.gpu0 ? root.gpu0.power : null }, root.fahrenheit).replace(/\d+°/, "100°").replace(/\d+W/, "999W")
  }

  Grid {
    id: row
    columns: root.vertical ? 1 : 3
    columnSpacing: Style.space(2)

    Section {
      id: cpuButton
      bar: root.bar
      theme: root.theme
      text: root.vertical ? F.percent(root.live.cpu ? root.live.cpu.usage : null) : F.section("CPU", root.live.cpu, root.fahrenheit)
      fixedWidth: root.vertical ? -1 : Math.ceil(cpuMetrics.advanceWidth) + Style.space(14) + root.dotRoom
      load: root.live.cpu && root.live.cpu.usage ? root.live.cpu.usage : 0
      stale: root.stale
      seq: root.seq
      spark: root.cpuSpark
      showSpark: root.prefs.sparklines
      showDot: root.prefs.heartbeat
      highlighted: root.activeReport === "cpu"
      tooltipText: root.activeReport === "" ? "CPU — click or rest here for details" : ""
      onPressed: root.toggleReport("cpu")
    }
    Section {
      id: gpuButton
      bar: root.bar
      theme: root.theme
      visible: root.gpu0 !== null || root.stale
      text: root.vertical ? F.percent(root.gpu0 ? root.gpu0.usage : null) : F.section("GPU", root.gpu0, root.fahrenheit)
      fixedWidth: root.vertical ? -1 : Math.ceil(gpuMetrics.advanceWidth) + Style.space(14) + root.dotRoom
      load: root.gpu0 && root.gpu0.usage ? root.gpu0.usage : 0
      stale: root.stale
      seq: root.seq
      spark: root.gpuSpark
      showSpark: root.prefs.sparklines
      showDot: root.prefs.heartbeat
      highlighted: root.activeReport === "gpu"
      tooltipText: root.activeReport === "" && root.gpu0 ? root.gpu0.name : ""
      onPressed: root.toggleReport("gpu")
    }
    Section {
      id: netButton
      bar: root.bar
      theme: root.theme
      text: root.vertical ? "SYS" : F.network(root.live.net)
      fixedWidth: root.vertical ? -1 : Math.ceil(netWidth.advanceWidth) + Style.space(14) + root.dotRoom
      load: root.live.mem && root.live.mem.usedPct ? root.live.mem.usedPct : 0
      stale: root.stale
      seq: root.seq
      spark: root.netSpark
      sparkCeiling: root.netPeak
      showSpark: root.prefs.sparklines
      showDot: root.prefs.heartbeat
      highlighted: root.activeReport === "system"
      tooltipText: root.activeReport === "" && root.live.mem ? "Memory " + F.percent(root.live.mem.usedPct) + " — network, disks, sensors" : ""
      onPressed: root.toggleReport("system")
    }
  }

  readonly property var detailCpu: detail.cpu || ({})
  readonly property var detailGpu: detail.gpu && detail.gpu[0] ? detail.gpu[0] : ({})

  Sheet { id: cpuSheet; reportId: "cpu"; title: "Processor"; subtitle: root.detailCpu.model || ""; host: root; anchorItem: cpuButton; bar: root.bar }
  Sheet { id: gpuSheet; reportId: "gpu"; title: "Graphics"; subtitle: root.detailGpu.vendor ? ({ nvidia: "NVIDIA", amd: "AMD", intel: "Intel" })[root.detailGpu.vendor] + (root.detailGpu.asleep ? " · asleep" : "") : ""; host: root; anchorItem: gpuButton; bar: root.bar }
  Sheet {
    id: systemSheet
    reportId: "system"
    title: "System"
    subtitle: root.detailCpu.uptime ? "Up " + F.duration(root.detailCpu.uptime) : ""
    host: root
    anchorItem: netButton
    bar: root.bar
  }
}
