import QtQuick
import qs.Commons

// A 270° gauge. The arc sweeps to each new reading; hot readings get a soft breathing halo.
Item {
  id: root
  property var theme
  property real value: 0
  property string text
  property string label
  property color fill: theme ? theme.foreground : "white"
  property real size: Style.space(66)

  property real shown: 0
  property real halo: 0
  readonly property real target: Math.max(0, Math.min(100, isNaN(value) ? 0 : value))
  readonly property bool hot: target >= 85

  width: size
  height: size + caption.implicitHeight + Style.space(3)

  onTargetChanged: shown = target
  Component.onCompleted: shown = target
  Behavior on shown { enabled: !!root.theme && root.theme.animate; NumberAnimation { duration: 750; easing.type: Easing.OutCubic } }
  onShownChanged: canvas.requestPaint()
  onHaloChanged: canvas.requestPaint()
  onFillChanged: canvas.requestPaint()

  SequentialAnimation on halo {
    running: root.hot && !!root.theme && root.theme.animate && root.visible
    loops: Animation.Infinite
    onRunningChanged: if (!running) root.halo = 0
    NumberAnimation { from: 0; to: 1; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1; to: 0; duration: 900; easing.type: Easing.InOutSine }
  }

  Canvas {
    id: canvas
    width: root.size
    height: root.size
    renderStrategy: Canvas.Cooperative
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var line = Math.max(3, root.size * 0.09)
      var r = (root.size - line) / 2 - 2
      var c = root.size / 2
      var start = Math.PI * 0.75, sweep = Math.PI * 1.5
      ctx.lineCap = "round"
      ctx.lineWidth = line
      ctx.strokeStyle = root.theme ? root.theme.track : "gray"
      ctx.beginPath(); ctx.arc(c, c, r, start, start + sweep); ctx.stroke()
      var f = root.shown / 100
      if (f <= 0.001) return
      if (root.halo > 0) {
        ctx.lineWidth = line + 4 * root.halo
        ctx.strokeStyle = Qt.rgba(root.fill.r, root.fill.g, root.fill.b, 0.18 + 0.12 * root.halo)
        ctx.beginPath(); ctx.arc(c, c, r, start, start + sweep * f); ctx.stroke()
      }
      var g = ctx.createLinearGradient(0, root.size, root.size, 0)
      g.addColorStop(0, Qt.rgba(root.fill.r * 0.75, root.fill.g * 0.75, root.fill.b * 0.75, 1))
      g.addColorStop(1, root.fill)
      ctx.lineWidth = line
      ctx.strokeStyle = g
      ctx.beginPath(); ctx.arc(c, c, r, start, start + sweep * f); ctx.stroke()
      // bright tip
      var a = start + sweep * f
      ctx.fillStyle = Qt.lighter(root.fill, 1.35)
      ctx.beginPath(); ctx.arc(c + r * Math.cos(a), c + r * Math.sin(a), line * 0.32, 0, Math.PI * 2); ctx.fill()
    }
  }

  Txt {
    theme: root.theme
    text: root.text
    anchors.centerIn: canvas
    width: root.size - Style.space(16)
    horizontalAlignment: Text.AlignHCenter
    font.pixelSize: Style.font.body
    font.weight: Font.DemiBold
  }
  Txt {
    id: caption
    theme: root.theme
    dim: true
    text: root.label
    anchors.top: canvas.bottom
    anchors.topMargin: Style.space(1)
    width: root.size
    horizontalAlignment: Text.AlignHCenter
    font.pixelSize: Style.font.caption
  }
}
