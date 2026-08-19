import QtQuick
import Quickshell.Io
import "CrashWatch.js" as Script

// Reconciles a systemd drop-in for omarchy-crash-watch.service — another unit entirely.
Item {
  id: watch

  property string moduleName: ""
  property bool suppress: false
  property string ignorePattern: ""

  property string error: ""

  // Built at call time, never bound: a handler runs before siblings re-evaluate.
  property string script: ""

  // `settings` is injected after construction, so onCompleted sees defaults; queue.
  property bool pending: false

  function reconcile() {
    if (!Script.ignoreIsWritable(watch.ignorePattern)) {
      error = "crashIgnore cannot contain quotes or newlines, or end in a backslash"
      return
    }
    error = ""
    if (toggle.running) {
      pending = true
      return
    }
    pending = false
    script = Script.buildScript(watch.moduleName, watch.suppress, watch.ignorePattern)
    toggle.running = true
  }

  Component.onCompleted: reconcile()
  onSuppressChanged: reconcile()
  onIgnorePatternChanged: reconcile()

  Process {
    id: toggle
    command: ["env", "-u", "BASH_ENV", "bash", "-c", watch.script]
    stderr: StdioCollector {
      onStreamFinished: {
        var message = String(text || "").trim()
        if (message !== "") watch.error = message.split("\n").pop()
      }
    }
    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0 && watch.error === "")
        watch.error = "could not update the crash-watch drop-in"
      if (watch.pending) {
        watch.pending = false
        watch.reconcile()
      }
    }
  }
}
