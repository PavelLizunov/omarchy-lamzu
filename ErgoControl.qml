import QtQuick
import qs.Commons
import qs.Ui

// A shared, wrapping control for profile tools and action rows. Native shell
// Button owns input and theme states; this only supplies consistent geometry.
Button {
  id: root
  property string caption: ""
  property string detail: ""
  property string marker: ""
  text: ""
  focusable: true
  fontSize: Style.font.bodySmall
  opacity: enabled ? 1 : 0.5
  width: Math.min(implicitWidth, parent.width)
  implicitWidth: Math.max(label.implicitWidth, detailLabel.implicitWidth)
    + horizontalPadding * 2 + (marker !== "" ? Style.space(22) : 0) + Style.normalBorderWidth * 2
  implicitHeight: Math.max(Style.space(34), Style.spacing.controlHeight, labels.implicitHeight
    + verticalPadding * 2 + Style.normalBorderWidth * 2)
  Accessible.role: Accessible.Button
  Accessible.name: caption
  Accessible.description: detail
  Accessible.onPressAction: if (root.enabled) root.clicked()

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: root.horizontalPadding + Style.normalBorderWidth
    anchors.rightMargin: root.horizontalPadding + Style.normalBorderWidth
      + (root.marker !== "" ? Style.space(22) : 0)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)
    Text {
      id: label
      width: parent.width
      text: root.caption
      textFormat: Text.PlainText
      color: root.selected ? Style.selectedStateColor(root.foreground, root.accent) : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.selected
      horizontalAlignment: root.leftAlign ? Text.AlignLeft : Text.AlignHCenter
      wrapMode: Text.Wrap
    }
    Text {
      id: detailLabel
      visible: root.detail !== ""
      width: parent.width
      text: root.detail
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: root.leftAlign ? Text.AlignLeft : Text.AlignHCenter
      wrapMode: Text.Wrap
    }
  }
  Text {
    anchors.right: parent.right
    anchors.rightMargin: root.horizontalPadding
    anchors.verticalCenter: parent.verticalCenter
    text: root.marker
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }
}
