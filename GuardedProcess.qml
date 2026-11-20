import QtQuick
import Quickshell.Io

// Process with bounded lifetime and output. Limits are enforced in the shared
// shell process, so a stuck or noisy child cannot grow collectors indefinitely.
Process {
  id: root

  property int timeoutMs: 10000
  property int terminateGraceMs: 1000
  property int maxStdoutBytes: 1048576
  property int maxStderrBytes: 65536
  property bool timedOut: false
  property bool outputExceeded: false
  property string exceededStream: ""

  signal stdoutComplete(string text)
  signal stderrComplete(string text)
  signal guardedExited(int exitCode, int exitStatus)

  function failForOutput(stream) {
    if (outputExceeded) return
    outputExceeded = true
    exceededStream = stream
    // Stop the producer immediately: continuing to drain defeats the bound.
    if (running) signal(9)
  }

  function failureMessage(label) {
    if (timedOut) return label + " timed out after " + timeoutMs + " ms"
    if (outputExceeded)
      return label + " exceeded the " + exceededStream + " limit"
    return ""
  }

  stdout: StdioCollector {
    // `data` is an ArrayBuffer in Qt 6. Stream updates are required so the
    // producer is stopped near the bound instead of only after EOF.
    waitForEnd: false
    onDataChanged: {
      if (data.byteLength > root.maxStdoutBytes) root.failForOutput("stdout")
    }
    onStreamFinished: {
      if (!root.timedOut && !root.outputExceeded) root.stdoutComplete(text)
    }
  }

  stderr: StdioCollector {
    waitForEnd: false
    onDataChanged: {
      if (data.byteLength > root.maxStderrBytes) root.failForOutput("stderr")
    }
    onStreamFinished: {
      if (!root.timedOut && !root.outputExceeded) root.stderrComplete(text)
    }
  }

  property Timer deadline: Timer {
    interval: root.timeoutMs
    onTriggered: {
      root.timedOut = true
      if (root.running) {
        root.signal(15)
        forceKill.restart()
      }
    }
  }

  property Timer forceKill: Timer {
    id: forceKill
    interval: root.terminateGraceMs
    onTriggered: if (root.running) root.signal(9)
  }

  onStarted: {
    timedOut = false
    outputExceeded = false
    exceededStream = ""
    deadline.restart()
  }

  onExited: function (exitCode, exitStatus) {
    deadline.stop()
    forceKill.stop()
    root.guardedExited(exitCode, exitStatus)
  }
}
