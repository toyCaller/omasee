.pragma library

function sectionAt(x, y, rects) {
  for (var i = rects.length - 1; i >= 0; i--) {
    var r = rects[i]
    if (x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height) return r.id
  }
  return ""
}

// `hyprctl cursorpos -j` → { x, y } or null.
function parseCursor(text) {
  if (typeof text !== "string" || text.length > 256) return null
  try {
    var p = JSON.parse(text)
    if (p && typeof p.x === "number" && typeof p.y === "number" && isFinite(p.x) && isFinite(p.y)) return { x: p.x, y: p.y }
  } catch (e) {}
  return null
}

var STILL_PX = 8

// Tells someone heading for a card (they stop) from someone crossing the report
// on the way elsewhere (they keep moving). Pass null to start.
function trackPass(t, x, y, now, limitMs) {
  if (!t) return { startedAt: now, x: x, y: y, settled: false, through: false }
  if (t.settled || t.through) return t
  var moved = Math.sqrt(Math.pow(x - t.x, 2) + Math.pow(y - t.y, 2))
  return { startedAt: t.startedAt, x: x, y: y, settled: moved < STILL_PX, through: moved >= STILL_PX && now - t.startedAt >= limitMs }
}
