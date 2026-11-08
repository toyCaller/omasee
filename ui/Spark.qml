import QtQuick

// Tiny sparkline drawn behind a bar section's text.
Canvas {
  id: root
  property var values: []
  property real ceiling: 100
  property color tint: "white"
  renderStrategy: Canvas.Cooperative
  onValuesChanged: requestPaint()
  onTintChanged: requestPaint()
  onWidthChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var n = values ? values.length : 0
    if (n < 2 || width <= 0 || height <= 0) return
    var top = Math.max(ceiling, 1e-9), step = width / (n - 1), h = height
    ctx.beginPath()
    ctx.moveTo(0, h)
    for (var i = 0; i < n; i++) ctx.lineTo(i * step, h - Math.min(1, Math.max(0, values[i] || 0) / top) * (h - 1))
    ctx.lineTo(width, h)
    ctx.closePath()
    var g = ctx.createLinearGradient(0, 0, 0, h)
    g.addColorStop(0, Qt.rgba(tint.r, tint.g, tint.b, 0.30))
    g.addColorStop(1, Qt.rgba(tint.r, tint.g, tint.b, 0.0))
    ctx.fillStyle = g
    ctx.fill()
  }
}
