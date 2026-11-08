import QtQuick
import qs.Commons
import qs.Ui

// The popup that hosts one report, anchored under its bar section.
PopupCard {
  id: root
  property string reportId
  property string title
  property string subtitle
  property var host

  owner: QtObject { function close() { root.host.closeReport(root.reportId) } }
  open: host.activeReport === reportId
  triggerMode: (host.editing || host.pinned) && open ? "click" : "hover"

  readonly property real inset: verticalContentInset
  contentWidth: fittedContentWidth((loader.item ? loader.item.implicitWidth : Style.space(340)) + inset)
  contentHeight: fittedContentHeight(loader.item ? loader.item.implicitHeight : Style.space(220))

  onContentWidthChanged: anchor.updateAnchor()
  onContentHeightChanged: anchor.updateAnchor()

  Loader {
    id: loader
    anchors.fill: parent
    active: root.open || root.visible
    sourceComponent: Board {
      title: root.title
      subtitle: root.subtitle
      reportId: root.reportId
      columns: root.host.draft && root.open ? root.host.draft : root.host.layouts[root.reportId]
      stats: root.host.detail
      seq: root.host.seq
      stale: root.host.stale
      theme: root.host.theme
      fahrenheit: root.host.fahrenheit
      editing: root.host.editing
      onEditRequested: root.host.beginEdit()
      onDoneRequested: root.host.saveDraft()
      onColumnsEdited: function(next) { root.host.draft = next }
    }
  }
}
