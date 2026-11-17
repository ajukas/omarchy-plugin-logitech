import QtQuick
import qs.Commons
import qs.Ui

// A label, its current value, and a slider under them.
Column {
  id: root

  property QtObject bar: null
  property string label: ""
  property string valueText: String(Math.round(slider.liveValue))
  property real value: 0
  property real minimum: 0
  property real maximum: 100
  property real step: 1
  property color foreground: Color.popups.text
  readonly property alias liveValue: slider.liveValue

  signal moved(real value)
  signal released(real value)

  spacing: Style.spacing.xs

  Item {
    width: parent.width
    height: labelText.implicitHeight

    Text {
      id: labelText
      text: root.label
      textFormat: Text.PlainText
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.right: parent.right
      text: root.valueText
      textFormat: Text.PlainText
      color: Qt.darker(root.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  PanelSlider {
    id: slider
    width: parent.width
    height: Style.spacing.controlHeight * 0.7
    bar: root.bar
    integer: true
    minimum: root.minimum
    maximum: root.maximum
    step: root.step
    value: root.value
    onMoved: function(v) { root.moved(v) }
    onReleased: function(v) { root.released(v) }
  }
}
