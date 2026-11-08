import QtQuick
import "../js/signals.js" as S

// Live graph. Curves are smoothed, fills fade to transparent, and on every new sample the
// whole trace glides one step left so the history flows instead of jumping. The newest
// point carries a small breathing beacon.
Canvas {
  id: root
  property var theme
  property var series: []          // [{ values: [...], color: color }]
  property string kind: "percent"
  property bool stacked: false
  property bool mirrored: false
  property int capacity: 120
  property int seq: 0
  readonly property bool animate: !!theme && theme.animate

  property real shift: 0
  property real beacon: 0

  renderStrategy: Canvas.Cooperative
  onSeriesChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()
  onShiftChanged: requestPaint()
  onBeaconChanged: requestPaint()
  onSeqChanged: if (animate) { glide.stop(); shift = 1; glide.start() }

  NumberAnimation { id: glide; target: root; property: "shift"; to: 0; duration: 1900; easing.type: Easing.Linear }
  SequentialAnimation on beacon {
    running: root.animate && root.visible
    loops: Animation.Infinite
    NumberAnimation { from: 0; to: 1; duration: 1100; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1; to: 0; duration: 1100; easing.type: Easing.InOutSine }
  }

  function step() { return width / (capacity - 1) }
  function xAt(i, n) { return width - (n - 1 - i - shift) * step() }

  function trace(ctx, pts) {
    ctx.moveTo(pts[0].x, pts[0].y)
    for (var i = 1; i < pts.length - 1; i++) {
      var mx = (pts[i].x + pts[i + 1].x) / 2, my = (pts[i].y + pts[i + 1].y) / 2
      ctx.quadraticCurveTo(pts[i].x, pts[i].y, mx, my)
    }
    if (pts.length > 1) ctx.lineTo(pts[pts.length - 1].x, pts[pts.length - 1].y)
  }

  function band(ctx, top, bottom, color, fadeTowards) {
    if (top.length === 0) return
    var c = Qt.color(color)
    ctx.beginPath()
    trace(ctx, top)
    for (var j = bottom.length - 1; j >= 0; j--) ctx.lineTo(bottom[j].x, bottom[j].y)
    ctx.closePath()
    var g = ctx.createLinearGradient(0, fadeTowards === "up" ? height : 0, 0, fadeTowards === "up" ? 0 : height)
    g.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.38))
    g.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.03))
    ctx.fillStyle = g
    ctx.fill()
    ctx.beginPath()
    trace(ctx, top)
    ctx.lineWidth = 1.6
    ctx.lineJoin = "round"
    ctx.strokeStyle = color
    ctx.stroke()
    var head = top[top.length - 1]
    ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, 0.16 + 0.22 * beacon)
    ctx.beginPath(); ctx.arc(head.x, head.y, 3 + 3 * beacon, 0, Math.PI * 2); ctx.fill()
    ctx.fillStyle = Qt.lighter(c, 1.3)
    ctx.beginPath(); ctx.arc(head.x, head.y, 2.2, 0, Math.PI * 2); ctx.fill()
  }

  function points(values, yFor) {
    var n = values.length, out = []
    for (var i = 0; i < n; i++) out.push({ x: xAt(i, n), y: yFor(values[i] === null ? 0 : values[i], i) })
    return out
  }

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    if (width <= 0 || height <= 0) return
    var h = height
    ctx.save()
    ctx.beginPath(); ctx.rect(0, 0, width, h); ctx.clip()

    ctx.strokeStyle = theme ? theme.grid : "#333"
    ctx.lineWidth = 1
    for (var g = 1; g <= 3; g++) {
      var gy = Math.round(h * g / 4) + 0.5
      ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(width, gy); ctx.stroke()
    }

    var lists = series.map(function(s) { return s.values || [] })

    if (mirrored) {
      var mr = S.range(kind, lists), mid = h / 2
      series.forEach(function(s, idx) {
        var dir = idx === 0 ? -1 : 1
        var vals = s.values || []
        var top = points(vals, function(v) { return mid + dir * Math.min(1, v / mr.max) * (mid - 3) })
        var base = top.map(function(p) { return { x: p.x, y: mid } })
        band(ctx, top, base, s.color, dir < 0 ? "up" : "down")
      })
      ctx.restore()
      return
    }

    if (stacked) {
      var floor = [], sr = S.range(kind, [])
      series.forEach(function(s) {
        var vals = s.values || []
        var below = vals.map(function(_, i) { return floor[i] || 0 })
        var total = vals.map(function(v, i) { return below[i] + (v || 0) })
        var y = function(v) { return h - Math.min(1, v / sr.max) * (h - 3) }
        band(ctx, points(total, y), points(below, y), s.color, "up")
        floor = total
      })
      ctx.restore()
      return
    }

    var r = S.range(kind, lists)
    series.forEach(function(s) {
      var top = points(s.values || [], function(v) {
        return h - Math.max(0, Math.min(1, (v - r.min) / (r.max - r.min))) * (h - 3)
      })
      band(ctx, top, top.map(function(p) { return { x: p.x, y: h } }), s.color, "up")
    })
    ctx.restore()
  }
}
