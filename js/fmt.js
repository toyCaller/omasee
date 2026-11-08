.pragma library

var NONE = "–"

function missing(v) { return v === null || v === undefined || typeof v !== "number" || isNaN(v) }

function percent(v) { return missing(v) ? NONE : Math.round(v) + "%" }

function temp(c, fahrenheit) {
  if (missing(c)) return NONE
  return Math.round(fahrenheit ? c * 9 / 5 + 32 : c) + "°"
}

function watts(v) { return missing(v) ? NONE : Math.round(v) + "W" }

function scaled(v, base, units) {
  var i = 0
  while (v >= base && i < units.length - 1) { v /= base; i++ }
  var text = i === 0 || v >= 100 ? String(Math.round(v)) : v.toFixed(1)
  return text + " " + units[i]
}

function bytes(v) { return missing(v) ? NONE : scaled(v, 1024, ["B", "KB", "MB", "GB", "TB", "PB"]) }

function rate(v) { return missing(v) ? NONE : scaled(v, 1000, ["B/s", "KB/s", "MB/s", "GB/s"]) }

function duration(s) {
  if (missing(s)) return NONE
  var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
  if (d > 0) return d + "d " + h + "h"
  if (h > 0) return h + "h " + m + "m"
  return m + "m"
}

function clock(mhz) {
  if (missing(mhz)) return NONE
  return mhz >= 1000 ? (mhz / 1000).toFixed(2) + " GHz" : Math.round(mhz) + " MHz"
}

// Bar text. Temperature and power are only shown when the machine reports them,
// so a laptop without RAPL doesn't carry a permanent "–W".
function section(label, d, fahrenheit) {
  d = d || {}
  var parts = [label, percent(d.usage)]
  if (!missing(d.temp)) parts.push(temp(d.temp, fahrenheit))
  if (!missing(d.power)) parts.push(watts(d.power))
  return parts.join(" ")
}

function network(n) {
  n = n || {}
  return "↓ " + rate(n.down) + "  ↑ " + rate(n.up)
}

function plural(n, word) { return n + " " + word + (n === 1 ? "" : "s") }
