import QtQuick
import qs.Commons
import "../js/deck.js" as D

// One report: header with a live heartbeat, then up to three columns of cards.
Item {
  id: root

  property string title
  property string subtitle
  property string reportId
  property var columns: [[]]
  property var stats: ({})
  property var theme
  property bool fahrenheit: false
  property bool editing: false
  property bool stale: false
  property int seq: 0
  property int addingTo: -1

  signal editRequested()
  signal doneRequested()
  signal columnsEdited(var next)

  readonly property real columnWidth: Style.space(340)
  readonly property real gap: Style.space(9)

  implicitWidth: columns.length * columnWidth + (columns.length - 1) * gap
  implicitHeight: header.height + gap + grid.implicitHeight

  onEditingChanged: addingTo = -1

  function apply(name, col, index) {
    var ops = {
      remove: function() { return D.remove(columns, col, index) },
      up: function() { return D.moveVertical(columns, col, index, -1) },
      down: function() { return D.moveVertical(columns, col, index, 1) },
      left: function() { return D.moveAcross(columns, col, index, -1) },
      right: function() { return D.moveAcross(columns, col, index, 1) },
      size: function() { return D.cycleSize(columns, col, index) },
      metric: function() { return D.cycleMetric(columns, col, index) }
    }
    if (ops.hasOwnProperty(name)) columnsEdited(ops[name]())
  }

  Item {
    id: header
    width: parent.width
    height: Math.max(titleCol.implicitHeight, Style.space(26))

    // Heartbeat: flashes on every sample, idles in a slow breath, greys out when stale.
    Item {
      id: heart
      width: Style.space(10)
      height: width
      anchors.verticalCenter: titleCol.verticalCenter
      readonly property color tone: root.stale ? root.theme.faint : root.theme.color("green")
      Rectangle {
        id: ripple
        anchors.centerIn: parent
        width: parent.width; height: width; radius: width / 2
        color: "transparent"
        border.width: 1.5
        border.color: heart.tone
        opacity: 0
      }
      Rectangle {
        id: core
        anchors.centerIn: parent
        width: parent.width * 0.7; height: width; radius: width / 2
        color: heart.tone
        SequentialAnimation on opacity {
          running: root.theme.animate && !root.stale && root.visible
          loops: Animation.Infinite
          NumberAnimation { to: 0.5; duration: 1200; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1; duration: 1200; easing.type: Easing.InOutSine }
        }
      }
      ParallelAnimation {
        id: beat
        NumberAnimation { target: ripple; property: "scale"; from: 0.7; to: 2.4; duration: 900; easing.type: Easing.OutCubic }
        NumberAnimation { target: ripple; property: "opacity"; from: 0.85; to: 0; duration: 900; easing.type: Easing.OutCubic }
      }
      Connections {
        target: root
        function onSeqChanged() { if (root.theme.animate && !root.stale) beat.restart() }
      }
    }

    Column {
      id: titleCol
      anchors.left: heart.right
      anchors.leftMargin: Style.space(9)
      anchors.right: tools.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      Txt {
        width: parent.width
        theme: root.theme
        text: root.title
        font.pixelSize: Style.font.title
        font.weight: Font.DemiBold
      }
      Txt {
        width: parent.width
        visible: text !== ""
        theme: root.theme
        dim: true
        text: root.stale ? "Waiting for data…" : root.subtitle
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      id: tools
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
      Chip {
        visible: root.editing
        theme: root.theme
        text: "Reset"
        onClicked: root.columnsEdited(D.defaults()[root.reportId])
      }
      Chip {
        theme: root.theme
        emphasis: root.editing
        text: root.editing ? "Done" : "✎"
        onClicked: root.editing ? root.doneRequested() : root.editRequested()
      }
    }
  }

  Flickable {
    id: flick
    y: header.height + root.gap
    width: parent.width
    height: parent.height - y
    contentWidth: width
    contentHeight: grid.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Row {
      id: grid
      spacing: root.gap

      Repeater {
        model: root.columns

        Column {
          id: column
          required property var modelData
          required property int index
          width: root.columnWidth
          spacing: root.gap

          Repeater {
            model: column.modelData
            Card {
              required property var modelData
              required property int index
              spec: modelData
              stats: root.stats
              theme: root.theme
              fahrenheit: root.fahrenheit
              editing: root.editing
              seq: root.seq
              order: index + column.index * 2
              onAction: function(name) { root.apply(name, column.index, index) }
            }
          }

          Chip {
            visible: root.editing
            theme: root.theme
            text: root.addingTo === column.index ? "Cancel" : "+ Add card"
            onClicked: root.addingTo = root.addingTo === column.index ? -1 : column.index
          }
          Flow {
            visible: root.editing && root.addingTo === column.index
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: Object.keys(D.catalog)
              Chip {
                required property string modelData
                theme: root.theme
                text: D.catalog[modelData].label
                onClicked: { root.columnsEdited(D.add(root.columns, column.index, modelData)); root.addingTo = -1 }
              }
            }
          }
        }
      }
    }
  }
}
