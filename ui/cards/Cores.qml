import QtQuick
import qs.Commons
import ".."
import "../../js/signals.js" as S
import "../../js/fmt.js" as F

Column {
  id: root
  property var host
  readonly property var cpu: (host.stats && host.stats.cpu) || ({})
  readonly property var cores: cpu.cores || []
  readonly property var pairs: (cpu.threads && cpu.threads.length) ? cpu.threads : cores.map(function(_, i) { return [i] })
  readonly property int rows: pairs.length && pairs[0].length > 1 ? 2 : 1
  readonly property real cellGap: Style.space(3)
  readonly property real cellWidth: pairs.length ? (width - cellGap * (pairs.length - 1)) / pairs.length : 0
  readonly property bool hasContent: cores.length > 0
  spacing: Style.space(5)

  Head {
    theme: root.host.theme
    title: "Cores"
    value: F.plural(root.pairs.length, "core") + " · " + F.plural(root.cores.length, "thread")
  }
  Repeater {
    model: root.rows
    Row {
      required property int index
      readonly property int rowIndex: index
      spacing: root.cellGap
      Repeater {
        model: root.pairs
        Rectangle {
          required property var modelData
          readonly property real load: root.cores[modelData[parent.rowIndex]] || 0
          width: root.cellWidth
          height: Style.space(root.rows > 1 ? 22 : 34)
          radius: Style.space(3)
          color: root.host.theme.track
          clip: true
          Rectangle {
            id: fillBar
            readonly property color tone: root.host.theme.color(S.level(parent.load))
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * Math.min(100, parent.load) / 100
            radius: parent.radius
            gradient: Gradient {
              GradientStop { position: 0; color: fillBar.tone }
              GradientStop { position: 1; color: Qt.darker(fillBar.tone, 1.4) }
            }
            Behavior on height { enabled: root.host.theme.animate; NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
          }
        }
      }
    }
  }
}
