import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Just Say bar widget: shows Voxtype's live state (from its state file) and
// the health of the local codex-asr bridge. Left click toggles dictation,
// middle click cancels, right click runs `justsay doctor` in a terminal.
BarWidget {
  id: root
  moduleName: "justsay"

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property int healthIntervalSec: Math.max(5, Number((root.settings && root.settings.healthIntervalSec) || 20))
  property string voxState: "idle"
  property string health: "unknown"   // ok | offline | login | service | unknown
  property string healthDetail: ""
  property string lastError: ""

  readonly property bool busy: voxState === "recording" || voxState === "streaming" || voxState === "transcribing"

  readonly property string glyph: {
    if (voxState === "recording" || voxState === "streaming") return "󰍬"
    if (voxState === "transcribing") return "󰔟"
    if (health !== "ok" && health !== "unknown") return "󰍭"
    return "󰍮"
  }

  readonly property string tip: {
    if (voxState === "recording" || voxState === "streaming") return "Just Say: listening… (Alt+Space to finish)"
    if (voxState === "transcribing") return "Just Say: transcribing in the cloud…"
    if (health === "ok") return "Just Say: ready (cloud)" + (lastError ? "\nLast error: " + lastError : "")
    return "Just Say: " + (healthDetail || "not ready")
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  FileView {
    id: stateFile
    path: root.runtimeDir ? root.runtimeDir + "/voxtype/state" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.voxState = String(text() || "idle").trim() || "idle"
    onLoadFailed: root.voxState = "idle"
  }

  Process {
    id: healthProc
    command: ["justsay", "health", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var h = JSON.parse(text)
          root.health = h.status || "unknown"
          root.healthDetail = h.detail || ""
          root.lastError = h.lastError || ""
        } catch (e) {
          root.health = "unknown"
          root.healthDetail = "justsay is not installed"
        }
      }
    }
  }

  Timer {
    interval: root.healthIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!healthProc.running) healthProc.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    active: root.busy
    tooltipText: root.tip
    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.MiddleButton) root.bar.run("voxtype record cancel")
      else if (b === Qt.RightButton) root.bar.run("omarchy-launch-floating-terminal-with-presentation justsay doctor")
      else root.bar.run("omarchy-dictation toggle")
    }
  }
}
