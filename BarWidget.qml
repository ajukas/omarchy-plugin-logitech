import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui

// Bar icon for the Logitech mouse, headset and webcam. The icon turns urgent
// when a battery is low; clicking opens a card with a tab per device.
// logi-helper.py does all the device I/O and answers in JSON.
BarWidget {
  id: root
  moduleName: "ajukas.logitech"

  readonly property int refreshSec: Math.max(10, Number(setting("refreshSec", 60)))
  readonly property int lowBattery: Number(setting("lowBattery", 10))
  readonly property bool autoApplyCamera: setting("autoApplyCamera", true) !== false

  readonly property string helper: String(Qt.resolvedUrl("logi-helper.py")).replace(/^file:\/\//, "")

  property var mouse: ({ present: false })
  property var headset: ({ present: false })
  property var camera: ({ present: false })
  property var mouseSettings: null
  property bool mouseSettingsLoading: false
  property string lastError: ""
  property string tab: "mouse"

  // Values the user just moved to, shown until the device confirms them, so a
  // slider does not jump back while its write is still queued.
  property var cameraOverrides: ({})

  readonly property var batteries: {
    var list = []
    if (mouse.present && mouse.battery !== undefined && mouse.battery !== null) list.push({ label: "Mouse", pct: mouse.battery })
    if (headset.present && headset.battery !== undefined && headset.battery !== null) list.push({ label: "Headset", pct: headset.battery })
    return list
  }
  readonly property bool lowAny: {
    for (var i = 0; i < batteries.length; i++)
      if (lowBattery > 0 && batteries[i].pct < lowBattery) return true
    return false
  }
  readonly property bool anyPresent: mouse.present || headset.present || camera.present

  // ---------------------------------------------------------------- audio

  readonly property var pwNodes: Pipewire.nodes ? Pipewire.nodes.values : []

  function isHeadsetNode(n) {
    var s = String(n.name || "") + " " + String(n.description || "")
    return /logitech|046d/i.test(s) && /headset/i.test(s)
  }

  readonly property var headsetSink: {
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (n && n.isSink && !n.isStream && isHeadsetNode(n)) return n
    }
    return null
  }

  readonly property var headsetSource: {
    for (var i = 0; i < pwNodes.length; i++) {
      var n = pwNodes[i]
      if (n && !n.isSink && !n.isStream && isHeadsetNode(n) && !/monitor/i.test(n.name || "")) return n
    }
    return null
  }

  PwObjectTracker {
    objects: [root.headsetSink, root.headsetSource].filter(function(n) { return n !== null })
  }

  // ---------------------------------------------------------------- helper

  function parse(text) {
    try { return JSON.parse(text) } catch (e) { return null }
  }

  function applyStatus(text) {
    var data = parse(text)
    if (!data) return
    var cameraWasPresent = camera.present
    mouse = data.mouse || { present: false }
    headset = data.headset || { present: false }
    camera = data.camera || { present: false }
    if (commandQueue.length === 0 && !cmdProc.running && Object.keys(pendingCamera).length === 0)
      cameraOverrides = ({})
    // Webcams forget their image settings when replugged or after a reboot.
    if (autoApplyCamera && camera.present && !cameraWasPresent && camera.saved && Object.keys(camera.saved).length > 0)
      runCommand(["camera-apply"])
  }

  // The headset is only queried when its cached reading is older than its
  // auto power-off (see logi-helper.py), unless fresh is set: opening the card
  // asks for a live reading since the headset is clearly in use then.
  property bool freshHeadset: false

  function refresh(fresh) {
    if (fresh) freshHeadset = true
    if (!statusProc.running) statusProc.running = true
  }

  function loadMouseSettings() {
    if (!mouse.present || !mouse.solaar || mouseProc.running) return
    mouseSettingsLoading = true
    mouseProc.running = true
  }

  // Writes run one at a time; the status is re-read once the queue drains.
  property var commandQueue: []

  function runCommand(args) {
    commandQueue = commandQueue.concat([args])
    if (!cmdProc.running) nextCommand()
  }

  function nextCommand() {
    if (commandQueue.length === 0) {
      refresh()
      return
    }
    var args = commandQueue[0]
    commandQueue = commandQueue.slice(1)
    cmdProc.command = ["python3", helper].concat(args)
    cmdProc.running = true
  }

  function commandDone(text) {
    var result = parse(text)
    lastError = result && result.ok === false ? String(result.error || "Falha") : ""
    var args = cmdProc.command || []
    if (String(args[2] || "") === "mouse-set") loadMouseSettings()
  }

  // Sliders emit on every pixel; only the last value of each control is written.
  property var pendingCamera: ({})

  function setCamera(name, value) {
    var v = Math.round(Number(value))
    var o = Object.assign({}, cameraOverrides)
    o[name] = v
    cameraOverrides = o
    var p = Object.assign({}, pendingCamera)
    p[name] = v
    pendingCamera = p
    cameraDebounce.restart()
  }

  function setMouse(setting, value) { runCommand(["mouse-set", setting, String(value)]) }
  function setHeadset(what, value) { runCommand(["headset-set", what, String(Math.round(value))]) }
  function resetCamera() { cameraOverrides = ({}); runCommand(["camera-reset"]) }
  function previewCamera() { runCommand(["camera-preview"]) }

  Process {
    id: statusProc
    command: ["python3", root.helper, "status", "--notify-below", String(root.lowBattery)]
      .concat(root.freshHeadset ? ["--fresh-headset"] : [])
    stdout: StdioCollector { onStreamFinished: root.applyStatus(text) }
    onRunningChanged: if (running) root.freshHeadset = false
  }

  Process {
    id: mouseProc
    command: ["python3", root.helper, "mouse-settings"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.mouseSettings = root.parse(text)
        root.mouseSettingsLoading = false
      }
    }
  }

  Process {
    id: cmdProc
    stdout: StdioCollector { onStreamFinished: root.commandDone(text) }
    onExited: Qt.callLater(root.nextCommand)
  }

  Timer {
    id: cameraDebounce
    interval: 120
    onTriggered: {
      var p = root.pendingCamera
      root.pendingCamera = ({})
      for (var key in p) root.runCommand(["camera-set", key, String(p[key])])
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Keep the card live while it is open: batteries and auto modes change.
  Timer {
    interval: 5000
    running: card.open
    repeat: true
    onTriggered: root.refresh()
  }

  // ---------------------------------------------------------------- bar

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // The bar forwards unhandled double-clicks to its background, which toggles
  // bar transparency. Opening and quickly closing the card is a double-click,
  // so take it here and treat its second click as a normal one.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onDoubleClicked: function(mouse) {
      mouse.accepted = true
      card.open = !card.open
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍽"
    active: root.lowAny
    dimmed: !root.anyPresent
    tooltipText: {
      var parts = []
      for (var i = 0; i < root.batteries.length; i++)
        parts.push(root.batteries[i].label + " " + root.batteries[i].pct + "%")
      if (root.camera.present) parts.push("Câmera conectada")
      return parts.length ? "Logitech · " + parts.join(" · ") : "Logitech · nenhum dispositivo"
    }
    onPressed: function(b) {
      if (b === Qt.LeftButton) card.open = !card.open
      else if (b === Qt.MiddleButton) root.previewCamera()
    }
  }

  PopupCard {
    id: card
    anchorItem: button
    owner: root
    bar: root.bar
    contentWidth: card.fittedContentWidth(Style.space(360))
    contentHeight: card.fittedContentHeight(panel.implicitHeight)

    onOpenChanged: if (open) {
      root.refresh(true)
      root.loadMouseSettings()
    }

    LogiPanel {
      id: panel
      anchors.fill: parent
      widget: root
    }
  }
}
