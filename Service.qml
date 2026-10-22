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

  // Off means no domstats at all: the root turns it on for the bar or an open popup.
  property bool statsEnabled: false
  property int statsInterval: 3

  // Bound from the view: the snapshot list follows whichever row is open.
  property string snapshotDomain: ""

  // Bound from the view: the detail probes follow whichever row is expanded.
  property string detailDomain: ""

  // ---- State -----------------------------------------------------------
  property var domains: []
  property var snapshots: []
  property string currentSnapshot: ""

  property string lastError: ""
  property string actionError: ""
  property bool busy: false

  property string busyDomain: ""

  // False until the first poll answers, so an empty list is not read as "none".
  property bool polled: false

  // armedDomain/armedVerb: the split halves, so a poll can disarm without parsing.
  property string armedAction: ""
  property string armedDomain: ""
  property string armedVerb: ""

  // What is left of the disarm window, 1 down to 0, for the controls to draw.
  property real armFraction: 0

  readonly property int runningCount: countState("running")
  readonly property int pausedCount: countState("paused")
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
    armFraction = 1
    disarm.restart()
    armTick.restart()
  }

  function clearArm() {
    disarm.stop()
    armTick.stop()
    armFraction = 0
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

  // Drives the countdown the armed control paints; the disarm timer still owns the end.
  Timer {
    id: armTick
    interval: 80
    repeat: true
    onTriggered: service.armFraction = Math.max(0, service.armFraction - interval / disarm.interval)
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

    polled = true
    lastError = result.error
    if (result.error !== "") {
      domains = []
      clearArm()
      shutdownAt = ({})
      clearStats()
      service.domainsLost()
      return
    }

    // Only assign on a real change: a fresh array rebuilds every delegate in the list.
    var changed = !Virsh.sameDomains(domains, result.domains)
    if (changed) domains = result.domains

    // A queued shutdown is answered once the domain is no longer running.
    releaseStalled(result.running)

    // The reason a domain is off is part of the detail, so a state change restates it.
    if (changed && detailDomain !== "") fetchDetail(detailDomain)

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

  // A different connection is a different set of domains, so nothing survives it.
  onUriChanged: {
    polled = false
    domains = []
    snapshots = []
    shutdownAt = ({})
    clearArm()
    clearStats()
    service.domainsLost()
    refresh()
  }

  // ---- Usage -----------------------------------------------------------
  // Its own map, never folded into `domains`: that would rebuild every row per sample.
  property var stats: ({})
  property var statsPrev: ({})

  readonly property bool sampling: statsEnabled && runningCount > 0 && !connectionDown

  function clearStats() {
    stats = ({})
    statsPrev = ({})
  }

  function sampleStats() {
    statsProbe.running = false
    statsProbe.running = true
  }

  function applyStats(text) {
    var at = Date.now()
    var samples = Virsh.parseDomStats(text)
    var next = ({})
    var prev = ({})
    for (var name in samples) {
      var sample = samples[name]
      prev[name] = { cpuTime: sample.cpuTime, at: at }
      next[name] = {
        cpu: Virsh.cpuPercent(statsPrev[name], sample.cpuTime, sample.vcpus, at),
        vcpus: sample.vcpus,
        memUsed: Virsh.memoryUsed(sample),
        memTotal: sample.current
      }
    }
    statsPrev = prev
    stats = next
  }

  Process {
    id: statsProbe
    command: Virsh.statsArgv(service.uri)
    stdout: StdioCollector {
      onStreamFinished: service.applyStats(text)
    }
    stderr: StdioCollector {}
  }

  Timer {
    running: service.sampling
    interval: service.statsInterval * 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: service.sampleStats()
  }

  // A percentage needs two samples, so the second comes early rather than a full tick on.
  Timer {
    running: service.sampling
    interval: 1000
    onTriggered: service.sampleStats()
  }

  // A stale previous sample would average across the gap, so stopping forgets it.
  onSamplingChanged: if (!sampling) clearStats()

  // ---- Stalled shutdowns -----------------------------------------------
  // virsh returns when the request is queued, so a guest that ignores ACPI leaves
  // the row looking exactly like a button that did nothing.
  property var shutdownAt: ({})

  // Ticks only while something is waiting; the views read it to re-evaluate waitedFor.
  property double clock: 0

  Timer {
    running: Object.keys(service.shutdownAt).length > 0
    interval: 1000
    repeat: true
    onTriggered: service.clock = Date.now()
  }

  // `now` is passed in rather than read here, so the caller's binding depends on it.
  function waitedFor(domain, now) {
    var at = shutdownAt[Virsh.key(domain)]
    return at === undefined ? 0 : Math.floor((Math.max(now, at) - at) / 1000)
  }

  function releaseStalled(running) {
    var keys = Object.keys(shutdownAt)
    if (keys.length === 0) return
    var next = ({})
    var dropped = false
    for (var i = 0; i < keys.length; i++) {
      // Given up on after five minutes, so a domain nobody force-killed stops nagging.
      if (!running[keys[i]] || Date.now() - shutdownAt[keys[i]] > 300000) {
        dropped = true
        continue
      }
      next[keys[i]] = shutdownAt[keys[i]]
    }
    if (dropped) shutdownAt = next
  }

  // ---- Actions ---------------------------------------------------------
  // One at a time, argv never a shell string. virsh returns when queued — hence settle.
  property var actionCommand: []

  function runAction(verb, domain) {
    var argv = Virsh.actionArgv(uri, verb, domain)
    if (argv === null) return
    if (!runCommand(argv, domain)) return
    if (verb === "shutdown") {
      var next = ({})
      for (var name in shutdownAt) next[name] = shutdownAt[name]
      next[Virsh.key(domain)] = Date.now()
      shutdownAt = next
      clock = Date.now()
    }
  }

  // Prebuilt argv for the verbs that need flags; never sourced from a setting.
  function runCommand(argv, domain) {
    if (busy) return false
    actionError = ""
    clearArm()
    actionCommand = argv
    busy = true
    busyDomain = domain
    action.running = true
    return true
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
      if (service.detailDomain !== "") service.fetchDetail(service.detailDomain)
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

  // ---- Domain detail ---------------------------------------------------
  // Two read-only probes, fetched on expand only — never on the poll tick.
  property var detail: ({ cpus: 0, memory: "" })
  property string detailReason: ""
  property var detailInfoCommand: []
  property var detailStateCommand: []

  function fetchDetail(domain) {
    if (domain === "") return
    detailInfoCommand = Virsh.domInfoArgv(uri, domain)
    detailInfo.running = false
    detailInfo.running = true
    detailStateCommand = Virsh.domStateArgv(uri, domain)
    detailState.running = false
    detailState.running = true
  }

  Process {
    id: detailInfo
    command: service.detailInfoCommand
    stdout: StdioCollector {
      onStreamFinished: service.detail = Virsh.parseDomInfo(text)
    }
    stderr: StdioCollector {}
  }

  Process {
    id: detailState
    command: service.detailStateCommand
    stdout: StdioCollector {
      onStreamFinished: service.detailReason = Virsh.parseDomState(text)
    }
    stderr: StdioCollector {}
  }

  // Driven by the property, not by whatever expanded the row, so no route in stales it.
  onDetailDomainChanged: {
    detail = ({ cpus: 0, memory: "" })
    detailReason = ""
    if (detailDomain !== "") fetchDetail(detailDomain)
  }

  // ---- Snapshots -------------------------------------------------------
  property var snapshotCommand: []
  property var currentCommand: []

  function fetchSnapshots(domain) {
    if (domain === "") return
    snapshotCommand = Virsh.snapshotListArgv(uri, domain)
    snapshotList.running = false
    snapshotList.running = true
    currentCommand = Virsh.snapshotCurrentArgv(uri, domain)
    snapshotCurrent.running = false
    snapshotCurrent.running = true
  }

  Process {
    id: snapshotList
    command: service.snapshotCommand
    stdout: StdioCollector {
      onStreamFinished: service.snapshots = Virsh.parseSnapshotList(text)
    }
    stderr: StdioCollector {}
  }

  // Errors on a domain with no snapshots at all, which is why stderr is dropped.
  Process {
    id: snapshotCurrent
    command: service.currentCommand
    stdout: StdioCollector {
      onStreamFinished: service.currentSnapshot = Virsh.parseSnapshotCurrent(text)
    }
    stderr: StdioCollector {}
  }

  // Driven by the property, not by whatever opened the view, so no route in stales it.
  onSnapshotDomainChanged: {
    snapshots = []
    currentSnapshot = ""
    if (snapshotDomain !== "") fetchSnapshots(snapshotDomain)
  }

  function createSnapshot(domain, name, description) {
    runCommand(Virsh.snapshotCreateArgv(uri, domain, name, description), domain)
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
