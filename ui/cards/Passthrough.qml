import QtQuick
import qs.Commons
import ".."

Column {
  id: root
  property var host
  readonly property var devices: (host.stats && host.stats.gpuPassthrough) || []
  readonly property bool hasContent: devices.length > 0
  spacing: Style.space(4)

  Head { theme: root.host.theme; title: "Passed-through GPUs" }
  Repeater {
    model: root.devices
    Pair { required property var modelData; theme: root.host.theme; label: modelData.name; value: "In a VM" }
  }
}
