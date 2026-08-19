import QtQuick
import qs.Commons
import "Settings.js" as Config
import "Interface.js" as Interface
import "Virsh.js" as Virsh

// The widget's shell.json entry, read as tunables and written back through the host.
QtObject {
  id: config

  property var entry: ({})
  property string moduleName: ""
  property var shell: null

  property string error: ""

  // The root owns `settings`; persist() hands the merged entry back for it to assign.
  signal persisted(var next)

  function read(name, fallback) {
    return Config.read(config.entry, name, fallback)
  }

  // ---- Tunables --------------------------------------------------------
  readonly property string uri: read("uri", "qemu:///session")
  readonly property string icon: read("icon", Interface.Glyph.widget)
  readonly property int interval: Math.max(2, read("interval", 10))
  readonly property bool showCount: read("showCount", false)
  readonly property bool confirmForceOff: read("confirmForceOff", true)
  readonly property bool confirmDiscardSaved: read("confirmDiscardSaved", true)
  readonly property bool confirmSnapshotRevert: read("confirmSnapshotRevert", true)
  readonly property bool showSnapshots: read("showSnapshots", true)
  // Floored, not theme-pure: a sharp theme would otherwise render every corner square.
  readonly property int radius: read("cornerRadius", Math.max(Style.cornerRadius, Style.space(6)))
  readonly property string manager: read("manager", "virt-manager -c " + Virsh.shq(uri))
  readonly property string onRightClick: read("onRightClick", manager)

  // Named consoleCommand, not console: `console` is a JS global in every QML scope.
  readonly property string consoleCommand: read("console", "virt-viewer --connect {uri} {name}")

  readonly property bool suppressCrashToasts: read("suppressCrashToasts", false)
  readonly property string crashIgnore: read("crashIgnore", "^qemu-system-")

  // ---- State light colours ---------------------------------------------
  // The one sanctioned hardcode: a state light must read green/red.
  readonly property string defaultColorRunning: "#3fb950"
  readonly property string defaultColorPaused: "#d29922"
  readonly property string defaultColorStopped: "#f85149"

  readonly property string colorRunningHex: String(read("colorRunning", defaultColorRunning))
  readonly property string colorPausedHex: String(read("colorPaused", defaultColorPaused))
  readonly property string colorStoppedHex: String(read("colorStopped", defaultColorStopped))

  readonly property color colorRunning: colorRunningHex
  readonly property color colorPaused: colorPausedHex
  readonly property color colorStopped: colorStoppedHex

  readonly property var colorSettings: Config.COLOR_SETTINGS

  function colorHex(name) {
    return name === "colorRunning" ? colorRunningHex
      : (name === "colorPaused" ? colorPausedHex : colorStoppedHex)
  }

  function colorValue(name) {
    return name === "colorRunning" ? colorRunning
      : (name === "colorPaused" ? colorPaused : colorStopped)
  }

  // ---- Writing back ----------------------------------------------------
  // The widget's only write to user config, and it replaces the entry wholesale.
  function persist(name, value) {
    var next = Config.mergeEntry(config.entry, config.moduleName, name, value)
    // Emitted first: throws the switch on the click, and re-fires every tunable.
    config.persisted(next)
    if (config.shell && typeof config.shell.updateEntryInline === "function") {
      config.error = ""
      config.shell.updateEntryInline(config.moduleName, next)
    } else {
      config.error = "could not save: the shell did not expose updateEntryInline"
    }
  }

  function persistColor(name, text) {
    var clean = String(text).trim()
    if (!Config.isColorHex(clean)) {
      config.error = "not a colour: use #rgb, #rrggbb or #aarrggbb"
      return false
    }
    config.error = ""
    persist(name, clean)
    return true
  }
}
