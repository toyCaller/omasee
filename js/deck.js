.pragma library
.import "signals.js" as S

// The card catalog. `file` is an explicit whitelist: a layout entry can never load
// anything outside ui/cards/. `metrics` are the choices a card cycles through;
// `sizes` is false for cards whose height comes from their content.
var GRAPHS = ["cpu.load", "cpu.temp", "cpu.power", "gpu.usage", "gpu.memory", "gpu.temp", "gpu.power",
              "net", "disk", "mem.used", "mem.pressure", "swap"]

var catalog = {
  graph: { label: "Live graph", file: "Graph", metrics: GRAPHS, sizes: true },
  dials: { label: "Dials", file: "Dials", metrics: ["cpu", "gpu", "mem"], sizes: false },
  cores: { label: "CPU cores", file: "Cores", sizes: false },
  vitals: { label: "Load and uptime", file: "Vitals", sizes: false },
  top: { label: "Top processes", file: "Top", metrics: ["cpu", "memory", "disk"], sizes: true },
  engines: { label: "GPU engines", file: "Engines", sizes: false },
  gpuApps: { label: "GPU processes", file: "GpuApps", sizes: true },
  passthrough: { label: "Passed-through GPUs", file: "Passthrough", sizes: false },
  links: { label: "Network interfaces", file: "Links", sizes: false },
  storage: { label: "Disk space", file: "Storage", sizes: false },
  memory: { label: "Memory and swap", file: "Memory", sizes: false },
  temps: { label: "Temperatures", file: "Temps", sizes: false },
  fans: { label: "Fans", file: "Fans", sizes: false }
}

var SIZES = ["s", "m", "l"]
var MAX_COLUMNS = 3
var MAX_CARDS = 12
var REPORTS = ["cpu", "gpu", "system"]

function card(kind, metric, size) {
  var out = { card: kind, size: size || "m" }
  if (metric) out.metric = metric
  return out
}

function defaults() {
  return {
    cpu: [[card("dials", "cpu"), card("graph", "cpu.load"), card("cores"), card("top", "cpu"), card("vitals")]],
    gpu: [[card("dials", "gpu"), card("graph", "gpu.usage"), card("engines"), card("gpuApps"), card("passthrough")]],
    system: [
      [card("graph", "net"), card("links"), card("storage"), card("graph", "disk"), card("top", "disk")],
      [card("dials", "mem"), card("memory"), card("top", "memory"), card("temps"), card("fans")]
    ]
  }
}

function sanitize(item) {
  if (!item || typeof item !== "object") return null
  var entry = catalog.hasOwnProperty(item.card) ? catalog[item.card] : null
  if (!entry) return null
  var metric = entry.metrics ? (entry.metrics.indexOf(item.metric) >= 0 ? item.metric : entry.metrics[0]) : null
  return card(item.card, metric, SIZES.indexOf(item.size) >= 0 ? item.size : "m")
}

function sanitizeColumns(cols) {
  if (!Array.isArray(cols) || cols.length === 0) return null
  var out = []
  for (var i = 0; i < cols.length && out.length < MAX_COLUMNS; i++) {
    if (!Array.isArray(cols[i])) continue
    var cards = cols[i].slice(0, MAX_CARDS).map(sanitize).filter(function(c) { return c !== null })
    if (cards.length) out.push(cards)
  }
  return out.length ? out : [[]]
}

function resolve(saved) {
  var out = defaults()
  var plain = null
  // Settings arrive as Qt sequences that fail Array.isArray until copied into plain JS.
  try { plain = saved ? JSON.parse(JSON.stringify(saved)) : null } catch (e) { plain = null }
  REPORTS.forEach(function(r) {
    var cols = plain && typeof plain === "object" ? sanitizeColumns(plain[r]) : null
    if (cols) out[r] = cols
  })
  return out
}

// Only reports that differ from the defaults are stored.
function overrides(layouts) {
  var base = defaults(), out = {}
  REPORTS.forEach(function(r) { if (JSON.stringify(layouts[r]) !== JSON.stringify(base[r])) out[r] = layouts[r] })
  return out
}

function copy(v) { return JSON.parse(JSON.stringify(v)) }

function compact(cols) {
  var out = cols.filter(function(c) { return c.length > 0 })
  return out.length ? out : [[]]
}

function moveVertical(cols, c, i, delta) {
  var out = copy(cols), t = i + delta
  if (t < 0 || t >= out[c].length) return out
  out[c].splice(t, 0, out[c].splice(i, 1)[0])
  return out
}

function moveAcross(cols, c, i, delta) {
  var out = copy(cols), t = c + delta
  if (t < 0) return out
  if (t >= out.length) {
    if (out.length >= MAX_COLUMNS || out[c].length < 2) return out
    out.push([])
  }
  if (out[t].length >= MAX_CARDS) return out
  out[t].push(out[c].splice(i, 1)[0])
  return compact(out)
}

function cycleSize(cols, c, i) {
  var out = copy(cols), it = out[c][i]
  if (catalog[it.card].sizes) it.size = SIZES[(SIZES.indexOf(it.size) + 1) % SIZES.length]
  return out
}

function cycleMetric(cols, c, i) {
  var out = copy(cols), it = out[c][i], m = catalog[it.card].metrics
  if (m) it.metric = m[(m.indexOf(it.metric) + 1) % m.length]
  return out
}

function remove(cols, c, i) {
  var out = copy(cols)
  out[c].splice(i, 1)
  return compact(out)
}

function add(cols, c, kind) {
  var out = copy(cols)
  if (!catalog.hasOwnProperty(kind) || out[c].length >= MAX_CARDS) return out
  var m = catalog[kind].metrics
  out[c].push(card(kind, m ? m[0] : null))
  return out
}

function metricLabel(item) {
  if (!item.metric) return ""
  if (item.card === "graph") return S.info[item.metric].title
  return ({ cpu: "CPU", gpu: "GPU", mem: "Memory", memory: "Memory", disk: "Disk" })[item.metric] || item.metric
}
