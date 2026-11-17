import QtQuick
import qs.Commons
import qs.Ui

// Glyph, device name and a battery line with a thin level bar.
Item {
  id: root

  property string glyph: ""
  property string name: ""
  property string detail: ""
  property var battery: null // 0-100, or null when unknown
  property bool charging: false
  property int lowBattery: 10
  property color foreground: Color.popups.text

  readonly property bool hasBattery: battery !== null && battery !== undefined
  readonly property bool low: hasBattery && lowBattery > 0 && battery < lowBattery && !charging

  implicitHeight: Math.max(icon.height, info.implicitHeight)

  OpticalGlyph {
    id: icon
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Style.font.display * 1.3
    height: width
    text: root.glyph
    fontSize: Style.font.display
    color: root.low ? Color.urgent : root.foreground
  }

  Column {
    id: info
    anchors.left: icon.right
    anchors.leftMargin: Style.spacing.xl
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.xs

    Text {
      width: parent.width
      text: root.name
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Text {
      width: parent.width
      visible: text !== ""
      text: root.hasBattery
        ? "Bateria " + root.battery + "%" + (root.charging ? " · carregando" : "") + (root.detail ? " · " + root.detail : "")
        : root.detail
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.low ? Color.urgent : Qt.darker(root.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Rectangle {
      visible: root.hasBattery
      width: parent.width
      height: Math.max(3, Style.space(3))
      radius: height / 2
      color: Util.alpha(root.foreground, 0.15)

      Rectangle {
        width: parent.width * Math.max(0, Math.min(100, root.battery || 0)) / 100
        height: parent.height
        radius: parent.radius
        color: root.low ? Color.urgent : (root.charging ? Color.accent : root.foreground)
      }
    }
  }
}
