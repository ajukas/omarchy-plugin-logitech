import QtQuick
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Card content: one tab per device. All state and writes live on `widget`
// (BarWidget.qml); this file only lays them out.
Item {
  id: root

  property var widget: null

  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property var mouse: widget.mouse
  readonly property var headset: widget.headset
  readonly property var camera: widget.camera
  readonly property var ms: widget.mouseSettings
  readonly property var sink: widget.headsetSink
  readonly property var source: widget.headsetSource

  readonly property var cameraLabels: ({
    brightness: "Brilho",
    contrast: "Contraste",
    saturation: "Saturação",
    sharpness: "Nitidez",
    gain: "Ganho",
    zoom_absolute: "Zoom",
    pan_absolute: "Enquadramento horizontal",
    tilt_absolute: "Enquadramento vertical",
    focus_automatic_continuous: "Foco automático",
    focus_absolute: "Foco",
    white_balance_automatic: "Balanço de branco automático",
    white_balance_temperature: "Temperatura de cor",
    auto_exposure: "Exposição",
    exposure_time_absolute: "Tempo de exposição",
    exposure_dynamic_framerate: "Reduzir FPS com pouca luz",
    backlight_compensation: "Compensação de contraluz",
    power_line_frequency: "Anti-cintilação"
  })

  readonly property var menuLabels: ({
    auto_exposure: { "1": "Manual", "3": "Automática" },
    power_line_frequency: { "0": "Desligado", "1": "50 Hz", "2": "60 Hz" }
  })

  function cameraValue(ctrl) {
    var o = widget.cameraOverrides[ctrl.name]
    return o !== undefined ? o : ctrl.value
  }

  implicitHeight: col.implicitHeight

  component Hint: Text {
    width: parent ? parent.width : 0
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    color: root.dim
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  Flickable {
    anchors.fill: parent
    contentWidth: width
    contentHeight: col.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: col
      width: parent.width
      spacing: Style.spacing.rowGap

      ButtonGroup {
        anchors.horizontalCenter: parent.horizontalCenter
        foreground: root.fg
        fontSize: Style.font.bodySmall
        focusable: false
        value: root.widget.tab
        options: [
          { value: "mouse", label: "Mouse", icon: "󰍽" },
          { value: "headset", label: "Headset", icon: "󰋎" },
          { value: "camera", label: "Câmera", icon: "󰖠" }
        ]
        onChanged: function(v) { root.widget.tab = v }
      }

      PanelSeparator { width: parent.width; foreground: root.fg }

      // ------------------------------------------------------------ mouse

      Column {
        width: parent.width
        spacing: Style.spacing.rowGap
        visible: root.widget.tab === "mouse"

        Hint {
          visible: !root.mouse.present
          text: "Nenhum mouse Logitech sem fio encontrado. Confira se o receptor está conectado e o mouse ligado."
        }

        DeviceHeader {
          visible: root.mouse.present
          width: parent.width
          glyph: "󰍽"
          name: root.mouse.name || "Mouse"
          battery: root.mouse.battery !== undefined ? root.mouse.battery : null
          charging: /^charging|full/i.test(root.mouse.status || "")
          detail: root.mouse.battery === null || root.mouse.battery === undefined ? (root.mouse.level || "") : ""
          lowBattery: root.widget.lowBattery
          foreground: root.fg
        }

        Hint {
          visible: root.mouse.present && !root.mouse.solaar
          text: "Para ajustar DPI e taxa de resposta, instale o solaar:\nsudo pacman -S solaar"
        }

        Hint {
          visible: root.widget.mouseSettingsLoading
          text: "Lendo configurações do mouse…"
        }

        Hint {
          visible: !!root.ms && root.ms.ok === false && root.mouse.solaar
          text: "Não foi possível ler o mouse: " + (root.ms ? root.ms.error : "")
          color: Color.urgent
        }

        SliderRow {
          id: dpiSlider
          visible: !!root.ms && !!root.ms.dpi
          width: parent.width
          bar: root.widget.bar
          foreground: root.fg
          label: "Sensibilidade"
          valueText: Math.round(liveValue) + " DPI"
          minimum: root.ms && root.ms.dpi ? root.ms.dpi.min : 100
          maximum: root.ms && root.ms.dpi ? root.ms.dpi.max : 25600
          step: root.ms && root.ms.dpi ? root.ms.dpi.step : 50
          value: root.ms && root.ms.dpi && root.ms.dpi.value ? root.ms.dpi.value : 800
          onReleased: function(v) {
            var s = step > 0 ? step : 50
            root.widget.setMouse("dpi", Math.round(v / s) * s)
          }
        }

        ButtonGroup {
          visible: dpiSlider.visible
          foreground: root.fg
          fontSize: Style.font.bodySmall
          focusable: false
          value: root.ms && root.ms.dpi ? String(root.ms.dpi.value) : ""
          options: [400, 800, 1600, 3200].filter(function(d) {
            return !root.ms || !root.ms.dpi || (d >= root.ms.dpi.min && d <= root.ms.dpi.max)
          }).map(String)
          onChanged: function(v) { root.widget.setMouse("dpi", v) }
        }

        PanelSectionHeader {
          visible: !!root.ms && !!root.ms.reportRate
          text: "TAXA DE RESPOSTA"
          foreground: root.fg
        }

        ButtonGroup {
          visible: !!root.ms && !!root.ms.reportRate
          foreground: root.fg
          fontSize: Style.font.bodySmall
          focusable: false
          value: root.ms && root.ms.reportRate ? String(root.ms.reportRate.value) : ""
          options: root.ms && root.ms.reportRate ? root.ms.reportRate.choices : []
          onChanged: function(v) { root.widget.setMouse("report_rate", v) }
        }
      }

      // ------------------------------------------------------------ headset

      Column {
        width: parent.width
        spacing: Style.spacing.rowGap
        visible: root.widget.tab === "headset"

        Hint {
          visible: !root.headset.present
          text: "Nenhum headset Logitech encontrado."
        }

        DeviceHeader {
          visible: root.headset.present
          width: parent.width
          glyph: "󰋎"
          name: root.headset.name || "Headset"
          battery: root.headset.battery !== undefined ? root.headset.battery : null
          charging: root.headset.batteryStatus === "BATTERY_CHARGING"
          detail: root.headset.batteryStatus === "BATTERY_UNAVAILABLE" ? "desligado" : ""
          lowBattery: root.widget.lowBattery
          foreground: root.fg
        }

        PanelSectionHeader {
          visible: !!root.sink || !!root.source
          text: "ÁUDIO"
          foreground: root.fg
        }

        SliderRow {
          visible: !!root.sink && !!root.sink.audio
          width: parent.width
          bar: root.widget.bar
          foreground: root.fg
          label: "Volume"
          valueText: Math.round(liveValue) + "%"
          minimum: 0
          maximum: 100
          step: 5
          value: root.sink && root.sink.audio ? Math.round(root.sink.audio.volume * 100) : 0
          opacity: root.sink && root.sink.audio && root.sink.audio.muted ? 0.5 : 1
          onMoved: function(v) { if (root.sink && root.sink.audio) root.sink.audio.volume = v / 100 }
        }

        Toggle {
          visible: !!root.source && !!root.source.audio
          width: parent.width
          label: "Microfone mudo"
          foreground: root.fg
          checked: !!root.source && !!root.source.audio && root.source.audio.muted
          onClicked: if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
        }

        Row {
          spacing: Style.spacing.controlGap
          visible: (!!root.sink && Pipewire.defaultAudioSink !== root.sink) || (!!root.source && Pipewire.defaultAudioSource !== root.source)

          Button {
            visible: !!root.sink && Pipewire.defaultAudioSink !== root.sink
            bordered: true
            foreground: root.fg
            fontSize: Style.font.bodySmall
            iconText: "󰓃"
            text: "Usar como saída"
            onClicked: Pipewire.preferredDefaultAudioSink = root.sink
          }

          Button {
            visible: !!root.source && Pipewire.defaultAudioSource !== root.source
            bordered: true
            foreground: root.fg
            fontSize: Style.font.bodySmall
            iconText: "󰍬"
            text: "Usar como microfone"
            onClicked: Pipewire.preferredDefaultAudioSource = root.source
          }
        }

        PanelSectionHeader {
          visible: root.headset.present
          text: "HEADSET"
          foreground: root.fg
        }

        Hint {
          visible: root.headset.present && !root.headset.headsetcontrol
          text: "Para bateria, sidetone e desligamento automático, instale o headsetcontrol:\nsudo pacman -S headsetcontrol"
        }

        SliderRow {
          visible: root.headset.present && root.headset.headsetcontrol
            && (!root.headset.capabilities || root.headset.capabilities.indexOf("sidetone") >= 0)
          width: parent.width
          bar: root.widget.bar
          foreground: root.fg
          label: "Sidetone (ouvir a própria voz)"
          valueText: Math.round(liveValue / 128 * 100) + "%"
          minimum: 0
          maximum: 128
          step: 8
          value: root.headset.sidetone !== null && root.headset.sidetone !== undefined ? root.headset.sidetone : 0
          onReleased: function(v) { root.widget.setHeadset("sidetone", v) }
        }

        Hint {
          visible: root.headset.present && root.headset.headsetcontrol
            && (!root.headset.capabilities || root.headset.capabilities.indexOf("inactive time") >= 0)
          text: "Desligar quando ocioso"
          color: root.fg
          font.pixelSize: Style.font.body
        }

        ButtonGroup {
          visible: root.headset.present && root.headset.headsetcontrol
            && (!root.headset.capabilities || root.headset.capabilities.indexOf("inactive time") >= 0)
          foreground: root.fg
          fontSize: Style.font.bodySmall
          focusable: false
          value: root.headset.inactive !== null && root.headset.inactive !== undefined ? String(root.headset.inactive) : ""
          options: [
            { value: "0", label: "Nunca" },
            { value: "5", label: "5m" },
            { value: "15", label: "15m" },
            { value: "30", label: "30m" },
            { value: "60", label: "60m" },
            { value: "90", label: "90m" }
          ]
          onChanged: function(v) { root.widget.setHeadset("inactive", v) }
        }
      }

      // ------------------------------------------------------------ camera

      Column {
        width: parent.width
        spacing: Style.spacing.rowGap
        visible: root.widget.tab === "camera"

        Hint {
          visible: !root.camera.present
          text: root.camera.v4l2 === false
            ? "Instale o v4l-utils para controlar a câmera:\nsudo pacman -S v4l-utils"
            : "Nenhuma webcam Logitech encontrada."
        }

        DeviceHeader {
          visible: root.camera.present
          width: parent.width
          glyph: "󰖠"
          name: root.camera.name || "Webcam"
          detail: root.camera.device || ""
          foreground: root.fg
        }

        Row {
          visible: root.camera.present
          spacing: Style.spacing.controlGap

          Button {
            bordered: true
            foreground: root.fg
            fontSize: Style.font.bodySmall
            iconText: "󰕧"
            text: "Prévia"
            tooltipText: "Abre a imagem da câmera no mpv"
            onClicked: root.widget.previewCamera()
          }

          Button {
            bordered: true
            foreground: root.fg
            fontSize: Style.font.bodySmall
            iconText: "󰑓"
            text: "Restaurar padrão"
            onClicked: root.widget.resetCamera()
          }
        }

        Repeater {
          model: root.camera.present ? root.camera.controls : []

          delegate: Item {
            id: ctrlRow
            required property var modelData
            readonly property var ctrl: modelData
            readonly property bool isBool: ctrl.type === "bool" || (ctrl.type === "int" && ctrl.min === 0 && ctrl.max === 1)
            readonly property string label: root.cameraLabels[ctrl.name] || ctrl.name
            readonly property int current: root.cameraValue(ctrl)

            width: parent ? parent.width : 0
            height: loader.item ? loader.item.implicitHeight : 0
            visible: !ctrl.inactive

            Loader {
              id: loader
              width: parent.width
              sourceComponent: ctrlRow.isBool ? boolControl : (ctrlRow.ctrl.type === "menu" ? menuControl : intControl)
            }

            Component {
              id: intControl

              SliderRow {
                bar: root.widget.bar
                foreground: root.fg
                label: ctrlRow.label
                minimum: ctrlRow.ctrl.min
                maximum: ctrlRow.ctrl.max
                step: Math.max(1, ctrlRow.ctrl.step || 1)
                value: ctrlRow.current
                valueText: ctrlRow.ctrl.name === "white_balance_temperature" ? Math.round(liveValue) + " K"
                  : ctrlRow.ctrl.name === "zoom_absolute" ? (liveValue / 100).toFixed(1) + "×"
                  : String(Math.round(liveValue))
                onMoved: function(v) { root.widget.setCamera(ctrlRow.ctrl.name, v) }
              }
            }

            Component {
              id: boolControl

              Toggle {
                label: ctrlRow.label
                foreground: root.fg
                checked: ctrlRow.current === 1
                onClicked: root.widget.setCamera(ctrlRow.ctrl.name, ctrlRow.current === 1 ? 0 : 1)
              }
            }

            Component {
              id: menuControl

              Column {
                spacing: Style.spacing.xs

                Text {
                  text: ctrlRow.label
                  textFormat: Text.PlainText
                  color: root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }

                ButtonGroup {
                  foreground: root.fg
                  fontSize: Style.font.bodySmall
                  focusable: false
                  value: String(ctrlRow.current)
                  options: (ctrlRow.ctrl.menu || []).map(function(m) {
                    var names = root.menuLabels[ctrlRow.ctrl.name] || {}
                    return { value: m.value, label: names[m.value] || m.label }
                  })
                  onChanged: function(v) { root.widget.setCamera(ctrlRow.ctrl.name, v) }
                }
              }
            }
          }
        }

        Hint {
          visible: root.camera.present
          text: root.widget.autoApplyCamera
            ? "Os ajustes são salvos e reaplicados quando a câmera é reconectada."
            : "Os ajustes são salvos; a reaplicação automática está desligada."
        }
      }

      Hint {
        visible: root.widget.lastError !== ""
        text: root.widget.lastError
        color: Color.urgent
      }
    }
  }
}
