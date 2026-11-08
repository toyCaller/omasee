import QtQuick
import qs.Commons
import ".."
import "../../js/signals.js" as S

Column {
  id: root
  property var host
  readonly property var def: S.info[host.spec.metric] || S.info["cpu.load"]
  readonly property var history: (host.stats && host.stats.history) || ({})
  readonly property real graphHeight: ({ s: Style.space(42), m: Style.space(72), l: Style.space(124) })[host.spec.size] || Style.space(72)
  spacing: Style.space(6)

  Head {
    theme: root.host.theme
    title: root.def.title
    value: S.current(root.host.stats, root.host.spec.metric, root.host.fahrenheit)
  }
  Wave {
    width: parent.width
    height: root.graphHeight
    theme: root.host.theme
    kind: root.def.kind
    stacked: !!root.def.stacked
    mirrored: !!root.def.mirrored
    seq: root.host.seq
    series: root.def.series.map(function(s) { return { values: root.history[s.key] || [], color: root.host.theme.color(s.color) } })
  }
  Item {
    width: parent.width
    implicitHeight: age.implicitHeight
    Row {
      spacing: Style.space(9)
      Repeater {
        model: root.def.series.length > 1 ? root.def.series : []
        Row {
          required property var modelData
          spacing: Style.space(4)
          Rectangle {
            width: Style.space(7); height: width; radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.host.theme.color(modelData.color)
          }
          Txt { theme: root.host.theme; dim: true; text: modelData.label; font.pixelSize: Style.font.caption }
        }
      }
      Txt {
        visible: text !== ""
        theme: root.host.theme
        dim: true
        font.pixelSize: Style.font.caption
        text: S.caption(root.host.stats, root.host.spec.metric, root.host.fahrenheit)
      }
    }
    Txt { id: age; anchors.right: parent.right; theme: root.host.theme; dim: true; text: "last 4 min"; font.pixelSize: Style.font.caption }
  }
}
