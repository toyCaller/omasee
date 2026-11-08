.pragma library

var defaults = {
  openDelayMs: 280,
  systemOpenDelayMs: 480,
  closeOnPassThrough: true,
  passThroughMs: 400,
  closeDelayMs: 300,
  animations: true,
  sparklines: true,
  heartbeat: true
}

var MAX_DELAY = 5000
var MAX_FILE = 16384

function delay(v, fallback) { return typeof v === "number" && isFinite(v) && v >= 0 && v <= MAX_DELAY ? Math.round(v) : fallback }
function flag(v, fallback) { return typeof v === "boolean" ? v : fallback }

// ~/.config/omasee/config.json. Anything missing, oversized or invalid uses its default.
function parse(text) {
  var r = {}
  if (typeof text === "string" && text.length <= MAX_FILE) {
    try {
      var p = JSON.parse(text)
      if (p && typeof p === "object" && !Array.isArray(p)) r = p
    } catch (e) {}
  }
  return {
    openDelayMs: delay(r.openDelayMs, defaults.openDelayMs),
    systemOpenDelayMs: delay(r.systemOpenDelayMs, defaults.systemOpenDelayMs),
    closeOnPassThrough: flag(r.closeOnPassThrough, defaults.closeOnPassThrough),
    passThroughMs: delay(r.passThroughMs, defaults.passThroughMs),
    closeDelayMs: delay(r.closeDelayMs, defaults.closeDelayMs),
    animations: flag(r.animations, defaults.animations),
    sparklines: flag(r.sparklines, defaults.sparklines),
    heartbeat: flag(r.heartbeat, defaults.heartbeat)
  }
}
