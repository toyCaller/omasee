import QtQuick
import qs.Commons
import "../js/deck.js" as D

// Frame around one card: rounded glass panel, staggered entrance, hover lift, and the
// editing toolbar. The card body is loaded from the catalog's whitelisted file name.
Rectangle {
  id: root

  property var spec
  property var stats
  property var theme
  property bool fahrenheit
  property bool editing
  property int seq: 0
  property int order: 0
  signal action(string name)

  readonly property var entry: spec && D.catalog.hasOwnProperty(spec.card) ? D.catalog[spec.card] : null
  readonly property bool hasContent: !loader.item || loader.item.hasContent !== false

  visible: editing || hasContent
  width: parent ? parent.width : 0
  implicitHeight: body.implicitHeight + Style.space(22)
  radius: Style.space(10)
  color: hover.hovered ? theme.cardHover : theme.card
  border.width: 1
  border.color: editing ? theme.alpha(theme.accent, 0.45) : theme.edge
  Behavior on color { enabled: root.theme.animate; ColorAnimation { duration: 180 } }

  // Entrance: fade and rise, one card after another.
  opacity: 0
  transform: Translate { id: lift; y: root.theme.animate ? Style.space(10) : 0 }
  Component.onCompleted: if (theme.animate) enter.start(); else opacity = 1
  SequentialAnimation {
    id: enter
    PauseAnimation { duration: Math.min(root.order, 10) * 45 }
    ParallelAnimation {
      NumberAnimation { target: root; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
      NumberAnimation { target: lift; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
    }
  }

  HoverHandler { id: hover }

  Column {
    id: body
    x: Style.space(11)
    y: Style.space(11)
    width: parent.width - Style.space(22)
    spacing: Style.space(7)

    Row {
      visible: root.editing
      width: parent.width
      spacing: Style.space(3)
      layoutDirection: Qt.RightToLeft
      Chip { theme: root.theme; text: "✕"; onClicked: root.action("remove") }
      Chip { theme: root.theme; text: "→"; onClicked: root.action("right") }
      Chip { theme: root.theme; text: "←"; onClicked: root.action("left") }
      Chip { theme: root.theme; text: "↓"; onClicked: root.action("down") }
      Chip { theme: root.theme; text: "↑"; onClicked: root.action("up") }
      Chip {
        theme: root.theme
        visible: !!root.entry && !!root.entry.sizes
        text: root.spec ? root.spec.size.toUpperCase() : ""
        onClicked: root.action("size")
      }
      Chip {
        theme: root.theme
        visible: !!root.entry && !!root.entry.metrics
        text: root.spec && root.spec.metric ? D.metricLabel(root.spec) + " ›" : ""
        onClicked: root.action("metric")
      }
    }

    Loader {
      id: loader
      width: parent.width
      asynchronous: true   // build cards off the critical path so a report opens instantly
      Component.onCompleted: if (root.entry) setSource("cards/" + root.entry.file + ".qml", { host: root })
    }
  }
}
