# Argument regression tests

Requirements: Node.js 18+ and `virsh` with libvirt's test driver.

```bash
node --test tests/virsh-arguments.cjs
```

The tests load the actual `Virsh.js` helpers without importing QML. Integration
tests keep each scenario in one ephemeral `test:///default` connection so that
snapshot state survives between commands. They never use QEMU system/session
connections, real guests or disk images.

Coverage includes leading-dash domain arguments and deletion/reversion of
snapshots named `--current`, `--children`, names with spaces and apostrophes.
Deleting a parent must preserve the other snapshot; reverting must select the
requested snapshot rather than implicitly using the current one.

This checks argv construction and real virsh parsing, not the graphical UI.
