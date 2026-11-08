import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// Omarchy exposes foreground/accent but graphs need several hues, so the current
// theme's colors.toml is read directly (read-only, regex-parsed, never evaluated).
QtObject {
  id: root

  property string fontFamily: ""
  property bool animate: true
  property var palette: ({})

  readonly property color foreground: Commons.Color.popups.text
  readonly property color accent: Commons.Color.popups.border
  readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  readonly property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.38)
  readonly property color card: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  readonly property color cardHover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.085)
  readonly property color edge: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08)
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  readonly property color grid: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.07)

  readonly property var roles: ({ red: "color1", green: "color2", yellow: "color3", orange: "color3",
                                  blue: "color4", magenta: "color5", cyan: "color6" })
  readonly property var fallbacks: ({ red: "#e06c75", green: "#98c379", yellow: "#e5c07b", orange: "#d19a66",
                                      blue: "#61afef", magenta: "#c678dd", cyan: "#56b6c2" })

  function color(name) {
    if (name === "muted") return muted
    if (name === "accent") return accent
    return palette[name] || palette[roles[name]] || fallbacks[name] || foreground
  }

  function alpha(c, a) { var q = Qt.color(c); return Qt.rgba(q.r, q.g, q.b, a) }

  function parse(text) {
    var next = {}
    if (typeof text === "string" && text.length < 65536) {
      var re = /^\s*([A-Za-z0-9_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/gm
      var m
      while ((m = re.exec(text)) !== null) next[m[1]] = m[2]
    }
    palette = next
  }

  function reload() { file.reload() }

  property FileView file: FileView {
    id: file
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.parse(text())
  }
}
