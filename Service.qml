import QtQuick
import Quickshell.Io
import "Virsh.js" as Virsh

// Everything that talks to virsh: polling, one-at-a-time actions, and snapshots.
Item {
  id: service

  // ---- Inputs ----------------------------------------------------------
  property string uri: "qemu:///session"
  property int interval: 10
  property bool confirmForceOff: true
  property bool confirmDiscardSaved: true
  property bool confirmSnapshotRevert: true

  // Bound from the view: the snapshot list follows whichever row is open.
  property string snapshotDomain: ""

  // ---- State -----------------------------------------------------------
  property var domains: []
  property var snapshots: []

  property string lastError: ""
  property string actionError: ""
  property bool busy: false

  property string busyDomain: ""

  // armedDomain/armedVerb: the split halves, so a poll can disarm without parsing.
  property string armedAction: ""
  property string armedDomain: ""
  property string armedVerb: ""

  readonly property int runningCount: countState("running")
  readonly property int totalCount: domains.length

  readonly property bool connectionDown: lastError !== ""

  // The view owns which row is open; a lost connection has to close them.
  signal domainsLost()

  // ---- Arm then confirm -------------------------------------------------
  function isArmed(verb, domain, snapshot) {
    return armedAction !== "" && armedAction === Virsh.armKey(verb, domain, snapshot)
  }

  function arm(verb, domain, snapshot) {
    armedAction = Virsh.armKey(verb, domain, snapshot)
    armedDomain = domain
    armedVerb = verb
    disarm.restart()
  }

  function clearArm() {
    disarm.stop()
    armedAction = ""
    armedDomain = ""
    armedVerb = ""
  }

  function confirmed(verb, domain, snapshot, confirm) {
    if (!confirm) return true
    if (isArmed(verb, domain, snapshot)) {
      clearArm()
      return true
    }
    arm(verb, domain, snapshot)
    return false
  }

  Timer {
    id: disarm
    interval: 4000
    onTriggered: service.clearArm()
  }

  // ---- Polling ---------------------------------------------------------
  function countState(state) {
    var found = 0
    for (var i = 0; i < domains.length; i++)
      if (domains[i].domainState === state) found++
    return found
  }

  function refresh() {
    poll.running = false
    poll.running = true
  }

  function applyPoll(text) {
    var result = Virsh.parsePoll(text)

    lastError = result.error
    if (result.error !== "") {
      domains = []
      clearArm()
      service.domainsLost()
      return
    }

    domains = result.domains

    // Disarm once the button being confirmed against is gone.
    if (armedDomain !== "") {
      var defined = false
      for (var k = 0; k < result.domains.length; k++)
        if (result.domains[k].name === armedDomain) defined = true
      var live = !!result.running[Virsh.key(armedDomain)] || !!result.paused[Virsh.key(armedDomain)]
      if (!defined || (armedVerb === "destroy" && !live))
        clearArm()
    }
  }

  // No `-l`, no BASH_ENV: a startup file's output would parse as a poll record.
  Process {
    id: poll
    command: ["env", "-u", "BASH_ENV", "bash", "-c", Virsh.pollScript(service.uri)]
    stdout: StdioCollector {
      onStreamFinished: service.applyPoll(text)
    }
  }

  Timer {
    running: true
    interval: service.interval * 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: service.refresh()
  }

  // ---- Actions ---------------------------------------------------------
  // One at a time, argv never a shell string. virsh returns when queued — hence settle.
  property var actionCommand: []

  function runAction(verb, domain) {
    var argv = Virsh.actionArgv(uri, verb, domain)
    if (argv !== null) runCommand(argv, domain)
  }

  // Prebuilt argv for the verbs that need flags; never sourced from a setting.
  function runCommand(argv, domain) {
    if (busy) return
    actionError = ""
    clearArm()
    actionCommand = argv
    busy = true
    busyDomain = domain
    action.running = true
  }

  function forceOff(domain) {
    if (confirmed("destroy", domain, "", confirmForceOff))
      runAction("destroy", domain)
  }

  function discardSaved(domain) {
    if (confirmed("managedsave-remove", domain, "", confirmDiscardSaved))
      runAction("managedsave-remove", domain)
  }

  Process {
    id: action
    command: service.actionCommand
    stdout: StdioCollector {}  // dropped; the popup shows state, not chatter
    stderr: StdioCollector {
      onStreamFinished: service.actionError = Virsh.lastLine(text)
    }
    onExited: function (exitCode, exitStatus) {
      service.busy = false
      service.busyDomain = ""
      if (exitCode === 0) service.actionError = ""
      settle.ticks = 0
      settle.restart()
      service.refresh()
      if (service.snapshotDomain !== "") service.fetchSnapshots(service.snapshotDomain)
    }
  }

  Timer {
    id: settle
    property int ticks: 0
    interval: 1200
    repeat: true
    onTriggered: {
      service.refresh()
      ticks++
      if (ticks >= 3) {
        ticks = 0
        stop()
      }
    }
  }

  // ---- Snapshots -------------------------------------------------------
  property var snapshotCommand: []

  function fetchSnapshots(domain) {
    if (domain === "") return
    snapshotCommand = Virsh.snapshotListArgv(uri, domain)
    snapshotList.running = false
    snapshotList.running = true
  }

  Process {
    id: snapshotList
    command: service.snapshotCommand
    stdout: StdioCollector {
      onStreamFinished: service.snapshots = Virsh.parseSnapshotList(text)
    }
    stderr: StdioCollector {}
  }

  // Driven by the property, not by whatever opened the view, so no route in stales it.
  onSnapshotDomainChanged: {
    snapshots = []
    if (snapshotDomain !== "") fetchSnapshots(snapshotDomain)
  }

  function createSnapshot(domain, name) {
    runCommand(Virsh.snapshotCreateArgv(uri, domain, name), domain)
  }

  function revertSnapshot(domain, name) {
    if (confirmed("snapshot-revert", domain, name, confirmSnapshotRevert))
      runCommand(Virsh.snapshotRevertArgv(uri, domain, name), domain)
  }

  function deleteSnapshot(domain, name) {
    if (confirmed("snapshot-delete", domain, name, confirmSnapshotRevert))
      runCommand(Virsh.snapshotDeleteArgv(uri, domain, name), domain)
  }
}
