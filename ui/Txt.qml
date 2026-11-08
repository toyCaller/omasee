import QtQuick
import qs.Commons

Text {
  property var theme
  property bool dim: false
  textFormat: Text.PlainText
  color: !theme ? "white" : dim ? theme.muted : theme.foreground
  font.family: theme ? theme.fontFamily : ""
  font.pixelSize: Style.font.bodySmall
  elide: Text.ElideRight
  renderType: Text.NativeRendering
  verticalAlignment: Text.AlignVCenter
}
