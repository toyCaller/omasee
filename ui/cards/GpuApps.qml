import QtQuick
import qs.Commons
import ".."
import "../../js/fmt.js" as F

Column {
  id: root
  property var host
  readonly property var rows: (host.stats && host.stats.gpu && host.stats.gpu[0] && host.stats.gpu[0].processes) || []
  readonly property int count: ({ s: 3, m: 6, l: 12 })[host.spec.size] || 6
  readonly property real typeW: Style.space(32)
  readonly property real useW: Style.space(40)
  readonly property real memW: Style.space(64)
  spacing: Style.space(2)

  component Line: Item {
    id: line
    property string name
    property string type
    property string use
    property string memory
    property bool dim: false
    width: root.width
    height: Style.space(20)
    Txt { theme: root.host.theme; dim: line.dim; text: line.name; anchors.left: parent.left; anchors.right: tl.left; anchors.rightMargin: Style.space(6); anchors.verticalCenter: parent.verticalCenter }
    Txt { id: tl; theme: root.host.theme; dim: true; text: line.type; width: root.typeW; horizontalAlignment: Text.AlignRight; anchors.right: ul.left; anchors.verticalCenter: parent.verticalCenter }
    Txt { id: ul; theme: root.host.theme; dim: line.dim; text: line.use; width: root.useW; horizontalAlignment: Text.AlignRight; anchors.right: ml.left; anchors.verticalCenter: parent.verticalCenter }
    Txt { id: ml; theme: root.host.theme; dim: line.dim; text: line.memory; width: root.memW; horizontalAlignment: Text.AlignRight; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
  }

  Head { theme: root.host.theme; title: "GPU processes"; value: root.rows.length ? String(root.rows.length) : "" }
  Line { name: "Name"; type: "Type"; use: "GPU"; memory: "Memory"; dim: true }
  Repeater {
    model: root.rows.slice(0, root.count)
    Line {
      required property var modelData
      name: modelData.name + (modelData.count > 1 ? "  ×" + modelData.count : "")
        + (modelData.encode > 0 ? "  enc " + modelData.encode + "%" : "")
        + (modelData.decode > 0 ? "  dec " + modelData.decode + "%" : "")
      type: modelData.type
      use: F.percent(modelData.usage)
      memory: modelData.memory ? F.bytes(modelData.memory) : F.NONE
    }
  }
  Txt { visible: root.rows.length === 0; theme: root.host.theme; dim: true; height: Style.space(20); text: "Nothing is using the GPU" }
}
